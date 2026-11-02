$ErrorActionPreference = 'Stop'

$Suites = @(
    [pscustomobject]@{ Name = 'Configuration.Tests.ps1'; Expected = 5 }
    [pscustomobject]@{ Name = 'Detection.Tests.ps1'; Expected = 14 }
    [pscustomobject]@{ Name = 'Validation.Tests.ps1'; Expected = 11 }
    [pscustomobject]@{ Name = 'Relationships.Tests.ps1'; Expected = 35 }
    [pscustomobject]@{ Name = 'RelationshipReporting.Tests.ps1'; Expected = 12 }
    [pscustomobject]@{ Name = 'CsvPreflight.Tests.ps1'; Expected = 13 }
)

$Results = @()
$TotalPassed = 0
$TotalFailed = 0

foreach ($Suite in $Suites) {
    $Path = Join-Path $PSScriptRoot $Suite.Name

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing test suite: $Path"
    }

    Write-Host "`n===== $($Suite.Name) =====" -ForegroundColor Cyan

    $OutputItems = @(& $Path 6>&1 2>&1)

    $OutputLines = @(
        foreach ($Item in $OutputItems) {
            if ($Item -is [System.Management.Automation.InformationRecord]) {
                [string]$Item.MessageData
            }
            else {
                [string]$Item
            }
        }
    )

    foreach ($Line in $OutputLines) {
        Write-Host $Line
    }

    $PassCount = @($OutputLines | Where-Object {
        $_ -match '^\s*\[PASS\]'
    }).Count

    $FailCount = @($OutputLines | Where-Object {
        $_ -match '^\s*\[FAIL\]'
    }).Count

    if ($PassCount -ne $Suite.Expected -or $FailCount -ne 0) {
        throw "$($Suite.Name): Expected $($Suite.Expected) passes and 0 failures; found $PassCount passes and $FailCount failures."
    }

    $TotalPassed += $PassCount

    $Results += [pscustomobject]@{
        Suite = $Suite.Name
        Passed = $PassCount
        Failed = $FailCount
        Status = 'PASS'
    }

    Write-Host "Verified: $PassCount passed, $FailCount failed." -ForegroundColor Green
}

Write-Host "`n===== FINAL REGRESSION RESULTS =====" -ForegroundColor Cyan
$Results | Format-Table -AutoSize

Write-Host "Suites executed: $($Results.Count)"
Write-Host "Total passed: $TotalPassed"
Write-Host "Total failed: $TotalFailed"

if ($Results.Count -ne 6 -or $TotalPassed -ne 90 -or $TotalFailed -ne 0) {
    throw 'Final regression verification failed.'
}

Write-Host "`nALL SIX SUITES VERIFIED: 90 PASSED, 0 FAILED." -ForegroundColor Green