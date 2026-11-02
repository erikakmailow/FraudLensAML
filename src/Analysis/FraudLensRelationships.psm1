$ErrorActionPreference = 'Stop'

$ValidationModule = Join-Path $PSScriptRoot '..\Core\TransactionValidation.psm1'

if (-not (Test-Path -LiteralPath $ValidationModule -PathType Leaf)) {
    throw "Transaction validation module not found: $ValidationModule"
}

Import-Module $ValidationModule -ErrorAction Stop

function New-FraudLensRelationshipGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Transactions
    )

    if ($Transactions.Count -eq 0) {
        throw 'At least one transaction is required.'
    }

    $ValidationResults = @(
        Test-FraudLensTransactions -Transactions $Transactions
    )

    $InvalidResults = @(
        $ValidationResults | Where-Object { -not $_.IsValid }
    )

    if ($InvalidResults.Count -gt 0) {
        $Details = @(
            $InvalidResults | ForEach-Object {
                '{0}: {1}' -f $_.TransactionId, ($_.Errors -join '; ')
            }
        )

        throw (
            'Relationship analysis rejected invalid transactions. ' +
            ($Details -join ' | ')
        )
    }

    $NodeLookup = @{}
    $EdgeLookup = @{}

    foreach ($Transaction in $Transactions) {
        $Sender = [string]$Transaction.SenderAccountId
        $Receiver = [string]$Transaction.ReceiverAccountId

        foreach ($AccountId in @($Sender, $Receiver)) {
            if (-not $NodeLookup.ContainsKey($AccountId)) {
                $NodeLookup[$AccountId] = [pscustomobject]@{
                    AccountId = $AccountId
                    InDegree = 0
                    OutDegree = 0
                }
            }
        }

        $Currency = ([string]$Transaction.Currency).ToUpperInvariant()

        $EdgeKey = '{0}:{1}:{2}:{3}:{4}:{5}' -f $Sender.Length, $Sender, $Receiver.Length, $Receiver, $Currency.Length, $Currency

        $Timestamp = [datetimeoffset]::Parse(
            [string]$Transaction.TimestampUtc,
            [Globalization.CultureInfo]::InvariantCulture
        ).ToUniversalTime()

        $Amount = [decimal]::Parse(
            [string]$Transaction.Amount,
            [Globalization.CultureInfo]::InvariantCulture
        )

        if (-not $EdgeLookup.ContainsKey($EdgeKey)) {
            $EdgeLookup[$EdgeKey] = [pscustomobject]@{
                SenderAccountId = $Sender
                ReceiverAccountId = $Receiver
                Currency = $Currency
                TransactionCount = 0
                TotalAmount = [decimal]0
                FirstTransactionUtc = $Timestamp
                LastTransactionUtc = $Timestamp
                TransactionIds = New-Object 'System.Collections.Generic.List[string]'
            }
        }

        $Edge = $EdgeLookup[$EdgeKey]

        $Edge.TransactionCount++
        $Edge.TotalAmount = [decimal]($Edge.TotalAmount + $Amount)
        $Edge.TransactionIds.Add([string]$Transaction.TransactionId)

        if ($Timestamp -lt $Edge.FirstTransactionUtc) {
            $Edge.FirstTransactionUtc = $Timestamp
        }

        if ($Timestamp -gt $Edge.LastTransactionUtc) {
            $Edge.LastTransactionUtc = $Timestamp
        }
    }

    foreach ($Edge in $EdgeLookup.Values) {
        $NodeLookup[$Edge.SenderAccountId].OutDegree++
        $NodeLookup[$Edge.ReceiverAccountId].InDegree++
    }

    $Nodes = @(
        $NodeLookup.Values |
            Sort-Object AccountId
    )

    $Edges = @(
        $EdgeLookup.Values |
            Sort-Object SenderAccountId, ReceiverAccountId, Currency |
            ForEach-Object {
                [pscustomobject]@{
                    SenderAccountId = $_.SenderAccountId
                    ReceiverAccountId = $_.ReceiverAccountId
                    Currency = $_.Currency
                    TransactionCount = $_.TransactionCount
                    TotalAmount = $_.TotalAmount
                    FirstTransactionUtc = $_.FirstTransactionUtc.ToString('o')
                    LastTransactionUtc = $_.LastTransactionUtc.ToString('o')
                    TransactionIds = @($_.TransactionIds.ToArray() | Sort-Object)
                }
            }
    )

    # Build undirected adjacency for connected-component discovery.
    # Original transaction edges remain directed.
    $Adjacency = @{}

    foreach ($AccountId in $NodeLookup.Keys) {
        $Adjacency[$AccountId] = New-Object 'System.Collections.Generic.List[string]'
    }

    foreach ($Edge in $EdgeLookup.Values) {
        $Adjacency[$Edge.SenderAccountId].Add($Edge.ReceiverAccountId)
        $Adjacency[$Edge.ReceiverAccountId].Add($Edge.SenderAccountId)
    }

    $Visited = @{}
    $ComponentList = New-Object 'System.Collections.Generic.List[object]'

    $SortedAccounts = @($NodeLookup.Keys | Sort-Object)

    foreach ($StartAccount in $SortedAccounts) {
        if ($Visited.ContainsKey($StartAccount)) {
            continue
        }

        $Stack = New-Object 'System.Collections.Generic.Stack[string]'
        $Stack.Push([string]$StartAccount)

        $ComponentAccounts = New-Object 'System.Collections.Generic.List[string]'

        while ($Stack.Count -gt 0) {
            $CurrentAccount = $Stack.Pop()

            if ($Visited.ContainsKey($CurrentAccount)) {
                continue
            }

            $Visited[$CurrentAccount] = $true
            $ComponentAccounts.Add($CurrentAccount)

            foreach ($Neighbor in @($Adjacency[$CurrentAccount] | Sort-Object -Descending)) {
                if (-not $Visited.ContainsKey($Neighbor)) {
                    $Stack.Push([string]$Neighbor)
                }
            }
        }

        $AccountIds = @($ComponentAccounts.ToArray() | Sort-Object)
        $AccountSet = @{}

        foreach ($AccountId in $AccountIds) {
            $AccountSet[$AccountId] = $true
        }

        $ComponentEdges = @(
            $EdgeLookup.Values | Where-Object {
                $AccountSet.ContainsKey($_.SenderAccountId) -and
                $AccountSet.ContainsKey($_.ReceiverAccountId)
            }
        )

        $TransactionIds = @(
            $ComponentEdges |
                ForEach-Object { $_.TransactionIds.ToArray() } |
                Sort-Object -Unique
        )

        $ComponentNumber = $ComponentList.Count + 1

        $ComponentList.Add([pscustomobject]@{
            ComponentId = 'FC-{0:D3}' -f $ComponentNumber
            AccountCount = $AccountIds.Count
            EdgeCount = $ComponentEdges.Count
            AccountIds = $AccountIds
            TransactionIds = $TransactionIds
        })
    }

    $Components = @($ComponentList.ToArray())
    [pscustomobject]@{
        AnalysisType = 'FraudLens Relationship Graph'
        SchemaVersion = '1.0'
        GeneratedAtUtc = [datetime]::UtcNow.ToString('o')
        NodeCount = $Nodes.Count
        EdgeCount = $Edges.Count
        TransactionCount = $Transactions.Count
        Nodes = $Nodes
        Edges = $Edges
        ComponentCount = $Components.Count
        Components = $Components
        Limitations = @(
            'Relationships represent observed synthetic transaction connections.',
            'A graph connection is not proof of misconduct.',
            'All findings require human review.'
        )
    }
}


function Find-FraudLensRelationshipPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Graph,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceAccountId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetAccountId,

        [ValidateRange(1, 10)]
        [int]$MaxHops = 3
    )

    if ($null -eq $Graph.Edges) {
        throw 'Graph does not contain an Edges collection.'
    }

    if ($SourceAccountId -eq $TargetAccountId) {
        return @()
    }

    $Adjacency = @{}

    foreach ($Edge in @($Graph.Edges)) {
        $Sender = [string]$Edge.SenderAccountId
        $Receiver = [string]$Edge.ReceiverAccountId

        if (-not $Adjacency.ContainsKey($Sender)) {
            $Adjacency[$Sender] = @{}
        }

        if (-not $Adjacency[$Sender].ContainsKey($Receiver)) {
            $Adjacency[$Sender][$Receiver] = @{}
        }

        $Currency = [string]$Edge.Currency
        if (-not $Adjacency[$Sender][$Receiver].ContainsKey($Currency)) {
            $Adjacency[$Sender][$Receiver][$Currency] = New-Object 'System.Collections.Generic.List[string]'
        }
        foreach ($TransactionId in @($Edge.TransactionIds)) {
            $Adjacency[$Sender][$Receiver][$Currency].Add([string]$TransactionId)
        }
    }

    if (-not $Adjacency.ContainsKey($SourceAccountId)) {
        return @()
    }

    $Stack = New-Object 'System.Collections.Generic.Stack[object]'

    $Stack.Push([pscustomobject]@{
        CurrentAccount = $SourceAccountId
        AccountIds = @($SourceAccountId)
        HopEvidence = @()
        HopCount = 0
    })

    $Results = New-Object 'System.Collections.Generic.List[object]'

    while ($Stack.Count -gt 0) {
        $State = $Stack.Pop()

        if ($State.HopCount -ge $MaxHops) {
            continue
        }

        if (-not $Adjacency.ContainsKey($State.CurrentAccount)) {
            continue
        }

        $Destinations = @(
            $Adjacency[$State.CurrentAccount].Keys | Sort-Object -Descending
        )

        foreach ($Destination in $Destinations) {
            if ($State.AccountIds -contains $Destination) {
                continue
            }

            $CurrencyEvidence = New-Object 'System.Collections.Generic.List[object]'
            $HopTransactionIdList = New-Object 'System.Collections.Generic.List[string]'

            foreach ($Currency in @($Adjacency[$State.CurrentAccount][$Destination].Keys | Sort-Object)) {
                $CurrencyTransactionIds = @(
                    $Adjacency[$State.CurrentAccount][$Destination][$Currency].ToArray() |
                        Sort-Object -Unique
                )

                foreach ($TransactionId in $CurrencyTransactionIds) {
                    $HopTransactionIdList.Add([string]$TransactionId)
                }

                $CurrencyEvidence.Add([pscustomobject]@{
                    Currency = [string]$Currency
                    TransactionIds = $CurrencyTransactionIds
                })
            }

            $HopTransactionIds = @($HopTransactionIdList.ToArray() | Sort-Object -Unique)

            $NewAccountIds = @($State.AccountIds) + @($Destination)

            $NewHopEvidence = @($State.HopEvidence) + @(
                [pscustomobject]@{
                    SenderAccountId = $State.CurrentAccount
                    ReceiverAccountId = $Destination
                    TransactionIds = $HopTransactionIds
                    CurrencyEvidence = @($CurrencyEvidence.ToArray())
                }
            )

            $NewHopCount = $State.HopCount + 1

            if ($Destination -eq $TargetAccountId) {
                $AllTransactionIds = @(
                    $NewHopEvidence |
                        ForEach-Object { $_.TransactionIds } |
                        Sort-Object -Unique
                )

                $Results.Add([pscustomobject]@{
                    SourceAccountId = $SourceAccountId
                    TargetAccountId = $TargetAccountId
                    HopCount = $NewHopCount
                    AccountIds = $NewAccountIds
                    TransactionIds = $AllTransactionIds
                    HopEvidence = $NewHopEvidence
                })

                continue
            }

            if ($NewHopCount -lt $MaxHops) {
                $Stack.Push([pscustomobject]@{
                    CurrentAccount = $Destination
                    AccountIds = $NewAccountIds
                    HopEvidence = $NewHopEvidence
                    HopCount = $NewHopCount
                })
            }
        }
    }

    $SortedResults = @(
        $Results.ToArray() |
            Sort-Object {
                $_.HopCount.ToString('D2') + '|' + ($_.AccountIds -join '|')
            }
    )

    return $SortedResults
}


function Find-FraudLensPassThroughActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Transactions,

        [ValidateRange(1, 720)]
        [int]$MaxElapsedHours = 24,

        [ValidateRange(0, 100)]
        [decimal]$AmountTolerancePercent = 10
    )

    if ($Transactions.Count -eq 0) {
        throw 'At least one transaction is required.'
    }

    $ValidationResult = @(Test-FraudLensTransactions -Transactions $Transactions)

    if ($ValidationResult.Count -ne $Transactions.Count) {
        throw 'Transaction validation did not return one result per input transaction.'
    }

    $InvalidRecords = @(
        $ValidationResult | Where-Object {
            $null -eq $_ -or
            $null -eq $_.PSObject.Properties['IsValid'] -or
            -not $_.IsValid
        }
    )

    if ($InvalidRecords.Count -gt 0) {
        $ErrorDetails = @(
            foreach ($InvalidRecord in $InvalidRecords) {
                $RecordId = $InvalidRecord.TransactionId
                $RecordErrors = @($InvalidRecord.Errors) -join '; '
                "$RecordId : $RecordErrors"
            }
        ) -join ' | '

        throw "Transaction validation failed. $ErrorDetails"
    }
    $ParsedTransactions = @()

    foreach ($Transaction in $Transactions) {
        $Timestamp = [DateTimeOffset]::MinValue
        $Amount = [decimal]0

        $TimestampValid = [DateTimeOffset]::TryParse(
            [string]$Transaction.TimestampUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$Timestamp
        )

        $AmountValid = [decimal]::TryParse(
            [string]$Transaction.Amount,
            [Globalization.NumberStyles]::Number,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$Amount
        )

        if (-not $TimestampValid -or -not $AmountValid) {
            throw "Unable to parse transaction $($Transaction.TransactionId)."
        }

        $ParsedTransactions += [pscustomobject]@{
            TransactionId = [string]$Transaction.TransactionId
            TimestampUtc = $Timestamp.ToUniversalTime()
            SenderAccountId = ([string]$Transaction.SenderAccountId).Trim()
            ReceiverAccountId = ([string]$Transaction.ReceiverAccountId).Trim()
            Amount = $Amount
            Currency = ([string]$Transaction.Currency).Trim().ToUpperInvariant()
        }
    }

    $Results = New-Object System.Collections.Generic.List[object]
    $MaximumElapsed = [TimeSpan]::FromHours($MaxElapsedHours)

    foreach ($Incoming in $ParsedTransactions) {
        foreach ($Outgoing in $ParsedTransactions) {

            if ($Incoming.ReceiverAccountId -ne $Outgoing.SenderAccountId) {
                continue
            }

            if ($Incoming.TransactionId -eq $Outgoing.TransactionId) {
                continue
            }

            if ($Outgoing.TimestampUtc -le $Incoming.TimestampUtc) {
                continue
            }

            $Elapsed = $Outgoing.TimestampUtc - $Incoming.TimestampUtc

            if ($Elapsed -gt $MaximumElapsed) {
                continue
            }

            if ($Incoming.Currency -ne $Outgoing.Currency) {
                continue
            }

            if ($Incoming.SenderAccountId -eq $Outgoing.ReceiverAccountId) {
                continue
            }

            if ($Incoming.Amount -le 0) {
                continue
            }

            $Difference = [Math]::Abs(
                [double]($Incoming.Amount - $Outgoing.Amount)
            )

            $DifferencePercent = (
                $Difference / [double]$Incoming.Amount
            ) * 100

            if ($DifferencePercent -gt [double]$AmountTolerancePercent) {
                continue
            }

            $Results.Add(
                [pscustomobject]@{
                    AnalysisType = 'PotentialPassThroughActivity'
                    AccountId = $Incoming.ReceiverAccountId
                    IncomingTransactionId = $Incoming.TransactionId
                    OutgoingTransactionId = $Outgoing.TransactionId
                    IncomingCounterparty = $Incoming.SenderAccountId
                    OutgoingCounterparty = $Outgoing.ReceiverAccountId
                    Currency = $Incoming.Currency
                    IncomingAmount = $Incoming.Amount
                    OutgoingAmount = $Outgoing.Amount
                    AmountDifference = [decimal]$Difference
                    AmountDifferencePercent = [Math]::Round($DifferencePercent, 2)
                    ElapsedMinutes = [Math]::Round($Elapsed.TotalMinutes, 2)
                    IncomingTimestampUtc = $Incoming.TimestampUtc
                    OutgoingTimestampUtc = $Outgoing.TimestampUtc
                    ReviewRequired = $true
                    Interpretation = 'Potential intermediary activity only. This analysis does not establish that the same funds were transferred or that misconduct occurred.'
                }
            )
        }
    }

    return @(
        $Results |
            Sort-Object AccountId, IncomingTimestampUtc, IncomingTransactionId, OutgoingTransactionId
    )
}

Export-ModuleMember -Function New-FraudLensRelationshipGraph, Find-FraudLensRelationshipPaths, Find-FraudLensPassThroughActivity
