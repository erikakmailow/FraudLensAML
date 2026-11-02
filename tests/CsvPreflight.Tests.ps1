$ErrorActionPreference = 'Stop'

$ModulePath = Join-Path $PSScriptRoot '..\src\Core\CsvPreflight.psm1'
Import-Module $ModulePath -Force

$Header = 'TransactionId,TimestampUtc,SenderAccountId,ReceiverAccountId,Amount,Currency,Channel'
$ValidRow = 'T001,2026-10-30T12:00:00Z,ACC001,ACC002,100.00,USD,Online'

$TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
    'FraudLensCsvTests-' + [guid]::NewGuid().ToString('N')
)

New-Item -ItemType Directory -Path $TempDirectory -Force | Out-Null

$Cases = @(
    [pscustomobject]@{
        Name = 'Valid CSV is accepted'
        Content = "$Header`r`n$ValidRow`r`n"
        ShouldPass = $true
        ExpectedDataRecords = 1
    }
    [pscustomobject]@{
        Name = 'Quoted comma is accepted'
        Content = "$Header`r`nT001,2026-10-30T12:00:00Z,ACC001,ACC002,100.00,USD,`"Online, Branch`"`r`n"
        ShouldPass = $true
        ExpectedDataRecords = 1
    }
    [pscustomobject]@{
        Name = 'Escaped quote is accepted'
        Content = "$Header`r`nT001,2026-10-30T12:00:00Z,ACC001,ACC002,100.00,USD,`"Wire `"`"Priority`"`"`"`r`n"
        ShouldPass = $true
        ExpectedDataRecords = 1
    }
    [pscustomobject]@{
        Name = 'UTF-8 BOM is accepted'
        Content = ([string][char]0xFEFF) + "$Header`r`n$ValidRow`r`n"
        ShouldPass = $true
        ExpectedDataRecords = 1
    }
    [pscustomobject]@{
        Name = 'Empty CSV is rejected'
        Content = ''
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Unclosed quoted field is rejected'
        Content = "$Header`r`nT001,2026-10-30T12:00:00Z,ACC001,ACC002,100.00,USD,`"Online"
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Quote inside unquoted field is rejected'
        Content = "$Header`r`nT001,2026-10-30T12:00:00Z,ACC001,ACC002,100.00,USD,On`"line`r`n"
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Unexpected character after closing quote is rejected'
        Content = "$Header`r`nT001,2026-10-30T12:00:00Z,ACC001,ACC002,100.00,USD,`"Online`"X`r`n"
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Incorrect header column count is rejected'
        Content = "TransactionId,TimestampUtc,SenderAccountId,ReceiverAccountId,Amount,Currency`r`n$ValidRow`r`n"
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Blank header is rejected'
        Content = "TransactionId,TimestampUtc,SenderAccountId,ReceiverAccountId,Amount,Currency,`r`n$ValidRow`r`n"
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Duplicate header is rejected'
        Content = "TransactionId,TimestampUtc,SenderAccountId,ReceiverAccountId,Amount,Currency,Currency`r`n$ValidRow`r`n"
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Missing required header is rejected'
        Content = "TransactionId,TimestampUtc,SenderAccountId,ReceiverAccountId,Amount,Currency,Method`r`n$ValidRow`r`n"
        ShouldPass = $false
    }
    [pscustomobject]@{
        Name = 'Inconsistent data field count is rejected'
        Content = "$Header`r`nT001,2026-10-30T12:00:00Z,ACC001,ACC002,100.00,USD`r`n"
        ShouldPass = $false
    }
)

$Passed = 0
$Failed = 0

try {
    foreach ($Case in $Cases) {
        $CsvPath = Join-Path $TempDirectory (
            'case-' + ($Passed + $Failed + 1) + '.csv'
        )

        [System.IO.File]::WriteAllText(
            $CsvPath,
            $Case.Content,
            (New-Object System.Text.UTF8Encoding($false))
        )

        $ActualPass = $false
        $Result = $null
        $ErrorMessage = $null

        try {
            $Result = Test-FraudLensCsv -Path $CsvPath -ErrorAction Stop
            $ActualPass = $true
        }
        catch {
            $ErrorMessage = $_.Exception.Message
        }

        $CasePassed = ($ActualPass -eq $Case.ShouldPass)

        if ($CasePassed -and $Case.ShouldPass) {
            $CasePassed = (
                $Result.HeaderCount -eq 7 -and
                $Result.DataRecordCount -eq $Case.ExpectedDataRecords
            )
        }

        if ($CasePassed) {
            $Passed++
            Write-Host "[PASS] $($Case.Name)" -ForegroundColor Green
        }
        else {
            $Failed++
            Write-Host "[FAIL] $($Case.Name)" -ForegroundColor Red

            if ($ErrorMessage) {
                Write-Host "       Error: $ErrorMessage"
            }
            elseif ($null -ne $Result) {
                Write-Host "       Header count: $($Result.HeaderCount)"
                Write-Host "       Data records: $($Result.DataRecordCount)"
            }
        }
    }
}
finally {
    Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== CSV PREFLIGHT TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Passed: $Passed"
Write-Host "Failed: $Failed"

if ($Failed -gt 0) {
    throw 'CSV preflight tests failed.'
}

Write-Host 'ALL CSV PREFLIGHT TESTS PASSED.' -ForegroundColor Green