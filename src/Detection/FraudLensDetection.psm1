Set-StrictMode -Version 2.0

function Invoke-FraudLensDetection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Transactions,

        [Parameter()]
        [switch]$UseConfig,

        [Parameter()]
        [string]$ConfigPath,

        [ValidateRange(1, 100)]
        [int]$NearThresholdMinimumCount = 3,

        [ValidateRange(1, 720)]
        [int]$NearThresholdWindowHours = 24,

        [ValidateRange(0.01, 1000000000)]
        [decimal]$NearThresholdMinimumAmount = 9000,

        [ValidateRange(0.01, 1000000000)]
        [decimal]$NearThresholdMaximumExclusive = 10000,

        [ValidateRange(2, 10000)]
        [int]$SharedCounterpartyMinimumSenders = 2
    )

$ConfigModule = Join-Path $PSScriptRoot '..\Core\DetectionConfiguration.psm1'
    if ($UseConfig) {
        Import-Module $ConfigModule -Force -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
            $Config = Import-FraudLensDetectionConfiguration -ErrorAction Stop
        }
        else {
            $Config = Import-FraudLensDetectionConfiguration -Path $ConfigPath -ErrorAction Stop
        }

        $NearThresholdMinimumCount = $Config.Rules.FL001.MinimumTransactionCount
        $NearThresholdWindowHours = $Config.Rules.FL001.WindowHours
        $NearThresholdMinimumAmount = $Config.Rules.FL001.MinimumAmountInclusive
        $NearThresholdMaximumExclusive = $Config.Rules.FL001.MaximumAmountExclusive
        $SharedCounterpartyMinimumSenders = $Config.Rules.FL002.MinimumDistinctSenders

        $EnableFL001 = [bool]$Config.Rules.FL001.Enabled
        $EnableFL002 = [bool]$Config.Rules.FL002.Enabled
    }
    if ($NearThresholdMinimumAmount -ge $NearThresholdMaximumExclusive) {
        throw 'Minimum amount must be less than the exclusive maximum.'
    }

    $ValidationPath = Join-Path $PSScriptRoot '..\Core\TransactionValidation.psm1'

    if (-not (Test-Path -LiteralPath $ValidationPath -PathType Leaf)) {
        throw "Validation module not found: $ValidationPath"
    }

    Import-Module $ValidationPath -ErrorAction Stop

    $Validation = @(Test-FraudLensTransactions -Transactions $Transactions)
    $Invalid = @($Validation | Where-Object { -not $_.IsValid })

    if ($Invalid.Count -gt 0) {
        $Details = @(
            $Invalid | ForEach-Object {
                '{0}: {1}' -f $_.TransactionId, ($_.Errors -join '; ')
            }
        )
        throw ("Input rejected; no detection performed. " + ($Details -join ' | '))
    }

    $Parsed = New-Object 'System.Collections.Generic.List[object]'

    foreach ($Transaction in $Transactions) {
        $Timestamp = [datetimeoffset]::MinValue
        $Amount = [decimal]0

        $TimestampOk = [datetimeoffset]::TryParse(
            [string]$Transaction.TimestampUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$Timestamp
        )

        $AmountOk = [decimal]::TryParse(
            [string]$Transaction.Amount,
            [Globalization.NumberStyles]::Number,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$Amount
        )

        if (-not $TimestampOk -or -not $AmountOk) {
            throw "Conversion failed for transaction $($Transaction.TransactionId)."
        }

        $Parsed.Add([pscustomobject]@{
            TransactionId = [string]$Transaction.TransactionId
            TimestampUtc = $Timestamp.ToUniversalTime()
            SenderAccountId = [string]$Transaction.SenderAccountId
            ReceiverAccountId = [string]$Transaction.ReceiverAccountId
            Amount = $Amount
            Currency = [string]$Transaction.Currency
            Channel = [string]$Transaction.Channel
        })
    }

    $Findings = New-Object 'System.Collections.Generic.List[object]'

    # FL-001: Repeated transactions within a configurable amount band.
    if (-not $UseConfig -or $EnableFL001) {
    $Eligible = @(
        $Parsed | Where-Object {
            $_.Amount -ge $NearThresholdMinimumAmount -and
            $_.Amount -lt $NearThresholdMaximumExclusive
        }
    )

    foreach ($SenderGroup in @($Eligible | Group-Object SenderAccountId)) {
        $Ordered = @(
            $SenderGroup.Group | Sort-Object TimestampUtc, TransactionId
        )

        for ($i = 0; $i -lt $Ordered.Count; $i++) {
            $WindowStart = $Ordered[$i].TimestampUtc
            $WindowEnd = $WindowStart.AddHours($NearThresholdWindowHours)

            $Window = @(
                $Ordered | Where-Object {
                    $_.TimestampUtc -ge $WindowStart -and
                    $_.TimestampUtc -le $WindowEnd
                }
            )

            if ($Window.Count -ge $NearThresholdMinimumCount) {
                $Ids = @(
                    $Window | ForEach-Object { $_.TransactionId }
                )

                # Use String.Format to avoid multiline -f parser ambiguity.
                $Explanation = [string]::Format(
                    [Globalization.CultureInfo]::InvariantCulture,
                    '{0} transactions from one sender were between {1} inclusive and {2} exclusive within {3} hours.',
                    [object[]]@(
                        $Window.Count,
                        $NearThresholdMinimumAmount,
                        $NearThresholdMaximumExclusive,
                        $NearThresholdWindowHours
                    )
                )

                $Findings.Add([pscustomobject]@{
                    FindingId = 'FL-001-' + $SenderGroup.Name
                    RuleId = 'FL-001'
                    RuleName = 'Repeated Near-Threshold Transactions'
                    Explanation = $Explanation
                    SenderAccountId = $SenderGroup.Name
                    ReceiverAccountId = $null
                    TransactionIds = $Ids
                    TransactionCount = $Window.Count
                    DistinctSenderCount = 1
                    WindowStartUtc = $WindowStart.ToString('o')
                    WindowEndUtc = $WindowEnd.ToString('o')
                    ReviewRequired = $true
                })

                # One finding per sender for this rule in v0.1.0.
                break
            }
        }
    }
    }

    # FL-002: Receiving accounts shared by multiple distinct senders.
    if (-not $UseConfig -or $EnableFL002) {
    foreach ($ReceiverGroup in @($Parsed | Group-Object ReceiverAccountId)) {
        $DistinctSenders = @(
            $ReceiverGroup.Group |
                Select-Object -ExpandProperty SenderAccountId -Unique
        )

        if ($DistinctSenders.Count -ge $SharedCounterpartyMinimumSenders) {
            $Ids = @(
                $ReceiverGroup.Group |
                    Sort-Object TimestampUtc, TransactionId |
                    ForEach-Object { $_.TransactionId }
            )

            $Explanation = [string]::Format(
                [Globalization.CultureInfo]::InvariantCulture,
                'The receiving account appears in transactions from {0} distinct sender accounts.',
                [object[]]@($DistinctSenders.Count)
            )

            $Findings.Add([pscustomobject]@{
                FindingId = 'FL-002-' + $ReceiverGroup.Name
                RuleId = 'FL-002'
                RuleName = 'Shared Receiving Account'
                Explanation = $Explanation
                SenderAccountId = $null
                ReceiverAccountId = $ReceiverGroup.Name
                TransactionIds = $Ids
                TransactionCount = $ReceiverGroup.Count
                DistinctSenderCount = $DistinctSenders.Count
                WindowStartUtc = $null
                WindowEndUtc = $null
                ReviewRequired = $true
            })
        }
    }
    }

    return $Findings.ToArray()
}

Export-ModuleMember -Function Invoke-FraudLensDetection
