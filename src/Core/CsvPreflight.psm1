Set-StrictMode -Version 2.0

function Read-FraudLensCsvRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "CSV file not found: $Path"
    }

    $Content = [System.IO.File]::ReadAllText($Path)

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw 'CSV file is empty.'
    }

    # Remove an optional UTF-8 BOM.
    if ($Content.Length -gt 0 -and [int]$Content[0] -eq 0xFEFF) {
        $Content = $Content.Substring(1)
    }

    $Records = New-Object 'System.Collections.Generic.List[object]'
    $Fields = New-Object 'System.Collections.Generic.List[string]'
    $Field = New-Object System.Text.StringBuilder

    $InQuotes = $false
    $AfterQuote = $false
    $AtFieldStart = $true

    for ($i = 0; $i -lt $Content.Length; $i++) {
        $Char = $Content[$i]

        if ($InQuotes) {
            if ($Char -eq '"') {
                if (($i + 1) -lt $Content.Length -and
                    $Content[$i + 1] -eq '"') {
                    [void]$Field.Append('"')
                    $i++
                }
                else {
                    $InQuotes = $false
                    $AfterQuote = $true
                }
            }
            else {
                [void]$Field.Append($Char)
            }

            continue
        }

        if ($AfterQuote) {
            if ($Char -eq ',') {
                $Fields.Add($Field.ToString())
                [void]$Field.Clear()
                $AfterQuote = $false
                $AtFieldStart = $true
                continue
            }

            if ($Char -eq "`r" -or $Char -eq "`n") {
                $Fields.Add($Field.ToString())
                [void]$Field.Clear()
                $Records.Add([pscustomobject]@{
                    Fields = @($Fields.ToArray())
                    RecordNumber = $Records.Count + 1
                })
                $Fields.Clear()
                $AfterQuote = $false
                $AtFieldStart = $true

                if ($Char -eq "`r" -and
                    ($i + 1) -lt $Content.Length -and
                    $Content[$i + 1] -eq "`n") {
                    $i++
                }

                continue
            }

            throw "Unexpected character after closing quote at character position $($i + 1)."
        }

        if ($Char -eq '"') {
            if (-not $AtFieldStart) {
                throw "Unexpected quote inside unquoted field at character position $($i + 1)."
            }

            $InQuotes = $true
            $AtFieldStart = $false
            continue
        }

        if ($Char -eq ',') {
            $Fields.Add($Field.ToString())
            [void]$Field.Clear()
            $AtFieldStart = $true
            continue
        }

        if ($Char -eq "`r" -or $Char -eq "`n") {
            $Fields.Add($Field.ToString())
            [void]$Field.Clear()
            $Records.Add([pscustomobject]@{
                Fields = @($Fields.ToArray())
                RecordNumber = $Records.Count + 1
            })
            $Fields.Clear()
            $AtFieldStart = $true

            if ($Char -eq "`r" -and
                ($i + 1) -lt $Content.Length -and
                $Content[$i + 1] -eq "`n") {
                $i++
            }

            continue
        }

        [void]$Field.Append($Char)
        $AtFieldStart = $false
    }

    if ($InQuotes) {
        throw 'CSV contains an unclosed quoted field.'
    }

    if ($AfterQuote -or
        $Field.Length -gt 0 -or
        $Fields.Count -gt 0 -or
        ($Content.Length -gt 0 -and
         $Content[$Content.Length - 1] -eq ',')) {

        $Fields.Add($Field.ToString())
        $Records.Add([pscustomobject]@{
            Fields = @($Fields.ToArray())
            RecordNumber = $Records.Count + 1
        })
    }

    if ($Records.Count -eq 0) {
        throw 'CSV contains no header record.'
    }

    return $Records.ToArray()
}

function Test-FraudLensCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $RequiredHeaders = @(
        'TransactionId',
        'TimestampUtc',
        'SenderAccountId',
        'ReceiverAccountId',
        'Amount',
        'Currency',
        'Channel'
    )

    $Records = @(Read-FraudLensCsvRecords -Path $Path)
    $Header = @($Records[0].Fields)

    if ($Header.Count -ne $RequiredHeaders.Count) {
        throw "CSV header must contain exactly $($RequiredHeaders.Count) columns."
    }

    foreach ($Name in $Header) {
        if ([string]::IsNullOrWhiteSpace($Name)) {
            throw 'CSV contains a blank header.'
        }
    }

    $DuplicateHeaders = @(
        $Header | Group-Object | Where-Object { $_.Count -gt 1 }
    )

    if ($DuplicateHeaders.Count -gt 0) {
        throw 'CSV contains duplicate column headers.'
    }

    foreach ($Required in $RequiredHeaders) {
        if ($Header -cnotcontains $Required) {
            throw "CSV is missing required column: $Required"
        }
    }

    for ($i = 1; $i -lt $Records.Count; $i++) {
        $Record = $Records[$i]

        if ($Record.Fields.Count -ne $Header.Count) {
            throw "CSV record $($Record.RecordNumber) contains $($Record.Fields.Count) fields; expected $($Header.Count)."
        }
    }

    return [pscustomobject]@{
        IsValid = $true
        HeaderCount = $Header.Count
        DataRecordCount = $Records.Count - 1
        Headers = $Header
    }
}

Export-ModuleMember -Function Test-FraudLensCsv
