Set-StrictMode -Version 2.0

function Test-FraudLensTransactions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Transactions
    )

    $RequiredColumns = @(
        'TransactionId',
        'TimestampUtc',
        'SenderAccountId',
        'ReceiverAccountId',
        'Amount',
        'Currency',
        'Channel'
    )

    # Count IDs across the entire batch before validating individual rows.
    # This ensures every record with a duplicated ID is rejected.
    $IdCounts = @{}

    foreach ($Item in $Transactions) {
        if ($null -eq $Item.PSObject.Properties['TransactionId']) {
            continue
        }

        $Id = [string]$Item.TransactionId

        if ([string]::IsNullOrWhiteSpace($Id)) {
            continue
        }

        if (-not $IdCounts.ContainsKey($Id)) {
            $IdCounts[$Id] = 0
        }

        $IdCounts[$Id]++
    }

    $Results = New-Object 'System.Collections.Generic.List[object]'

    foreach ($Transaction in $Transactions) {
        $Errors = New-Object 'System.Collections.Generic.List[string]'
        $TransactionId = ''

        if ($null -ne $Transaction.PSObject.Properties['TransactionId']) {
            $TransactionId = [string]$Transaction.TransactionId
        }

        foreach ($Column in $RequiredColumns) {
            if ($null -eq $Transaction.PSObject.Properties[$Column]) {
                $Errors.Add("Missing required field: $Column")
            }
        }

        if ($null -ne $Transaction.PSObject.Properties['TransactionId']) {
            if ([string]::IsNullOrWhiteSpace($TransactionId)) {
                $Errors.Add('TransactionId cannot be blank.')
            }
            elseif ($IdCounts.ContainsKey($TransactionId) -and
                    $IdCounts[$TransactionId] -gt 1) {
                $Errors.Add('Duplicate TransactionId.')
            }
        }

        # Validate the remaining fields that are present.
        if ($null -ne $Transaction.PSObject.Properties['SenderAccountId'] -and
            $null -ne $Transaction.PSObject.Properties['ReceiverAccountId']) {

            $Sender = [string]$Transaction.SenderAccountId
            $Receiver = [string]$Transaction.ReceiverAccountId

            if ([string]::IsNullOrWhiteSpace($Sender)) {
                $Errors.Add('SenderAccountId cannot be blank.')
            }

            if ([string]::IsNullOrWhiteSpace($Receiver)) {
                $Errors.Add('ReceiverAccountId cannot be blank.')
            }

            if (-not [string]::IsNullOrWhiteSpace($Sender) -and
                $Sender -eq $Receiver) {
                $Errors.Add('Sender and receiver cannot be identical.')
            }
        }

        if ($null -ne $Transaction.PSObject.Properties['TimestampUtc']) {
            $Timestamp = [datetimeoffset]::MinValue

            $TimestampValid = [datetimeoffset]::TryParse(
                [string]$Transaction.TimestampUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal,
                [ref]$Timestamp
            )

            if (-not $TimestampValid) {
                $Errors.Add('TimestampUtc is not a valid timestamp.')
            }
        }

        if ($null -ne $Transaction.PSObject.Properties['Amount']) {
            $Amount = [decimal]0

            $AmountValid = [decimal]::TryParse(
                [string]$Transaction.Amount,
                [Globalization.NumberStyles]::Number,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$Amount
            )

            if (-not $AmountValid -or $Amount -le 0) {
                $Errors.Add('Amount must be a valid positive number.')
            }
        }

        foreach ($Field in @('Currency', 'Channel')) {
            if ($null -ne $Transaction.PSObject.Properties[$Field] -and
                [string]::IsNullOrWhiteSpace([string]$Transaction.$Field)) {
                $Errors.Add("$Field cannot be blank.")
            }
        }

        $Results.Add([pscustomobject]@{
            TransactionId = $TransactionId
            IsValid       = ($Errors.Count -eq 0)
            Errors        = @($Errors.ToArray())
        })
    }

    return $Results.ToArray()
}

Export-ModuleMember -Function Test-FraudLensTransactions
