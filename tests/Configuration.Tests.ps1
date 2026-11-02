$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path $Root 'src\Core\DetectionConfiguration.psm1'
$ConfigPath = Join-Path $Root 'config\detection-rules.json'
$TempFiles = @()
$Passed = 0
$Failed = 0

Import-Module $ModulePath -Force -ErrorAction Stop

function Assert-Test {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    }
    catch {
        Write-Host "[FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:Failed++
    }
}

function Test-RejectedConfig {
    param([object]$Config)
    $Path = Join-Path $env:TEMP ('FraudLens-invalid-' + [guid]::NewGuid().ToString('N') + '.json')
    $script:TempFiles += $Path
    $Config | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $Path -Encoding UTF8
    $Rejected = $false
    try {
        Import-FraudLensDetectionConfiguration -Path $Path -ErrorAction Stop | Out-Null
    }
    catch {
        $Rejected = $true
    }
    if (-not $Rejected) {
        throw 'Invalid configuration was accepted.'
    }
}

try {
    $Original = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    Assert-Test 'Valid default configuration loads' {
        $Loaded = Import-FraudLensDetectionConfiguration -Path $ConfigPath
        if ($Loaded.Rules.FL001.MinimumTransactionCount -ne 3) {
            throw 'Unexpected FL-001 transaction-count default.'
        }
        if ($Loaded.Safety.AutomatedSarFiling -ne $false) {
            throw 'Automated SAR filing must remain disabled.'
        }
    }

    Assert-Test 'Invalid amount boundaries are rejected' {
        $Bad = $Original | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $Bad.Rules.'FL-001'.MinimumAmountInclusive = 10000
        $Bad.Rules.'FL-001'.MaximumAmountExclusive = 9000
        Test-RejectedConfig $Bad
    }

    Assert-Test 'Automated SAR filing cannot be enabled' {
        $Bad = $Original | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $Bad.Safety.AutomatedSarFiling = $true
        Test-RejectedConfig $Bad
    }

    Assert-Test 'Automated account decisions cannot be enabled' {
        $Bad = $Original | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $Bad.Safety.AutomatedAccountDecision = $true
        Test-RejectedConfig $Bad
    }

    Assert-Test 'Human review cannot be disabled' {
        $Bad = $Original | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $Bad.Safety.RequireHumanReview = $false
        Test-RejectedConfig $Bad
    }
}
finally {
    foreach ($File in $TempFiles) {
        Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nConfiguration tests: $Passed passed; $Failed failed."
if ($Failed -gt 0) {
    throw 'One or more configuration tests failed.'
}
