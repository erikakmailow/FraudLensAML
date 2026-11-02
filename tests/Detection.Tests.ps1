$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:USERPROFILE 'Documents\FraudLensAML'
$ModulePath = Join-Path $Root 'src\Detection\FraudLensDetection.psm1'
$CsvPath = Join-Path $Root 'data\synthetic\transactions.csv'

Import-Module $ModulePath -Force

$script:Passed = 0
$script:Failed = 0

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if ($Condition) {
        $script:Passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        $script:Failed++
        Write-Host "[FAIL] $Name" -ForegroundColor Red
    }
}

function New-TestTransaction {
    param(
        [string]$Id,
        [string]$Time,
        [string]$Sender,
        [string]$Receiver,
        [string]$Amount
    )

    [pscustomobject]@{
        TransactionId = $Id
        TimestampUtc = $Time
        SenderAccountId = $Sender
        ReceiverAccountId = $Receiver
        Amount = $Amount
        Currency = 'USD'
        Channel = 'Wire'
    }
}

# Test 1: Planted baseline scenarios
$Baseline = @(Import-Csv -LiteralPath $CsvPath)
$BaselineFindings = @(Invoke-FraudLensDetection -Transactions $Baseline)

$Near = @($BaselineFindings | Where-Object { $_.RuleId -eq 'FL-001' })
$Shared = @(
    $BaselineFindings | Where-Object {
        $_.RuleId -eq 'FL-002' -and
        $_.ReceiverAccountId -eq 'ACCT-SYN-900'
    }
)

Assert-Test 'Baseline has one FL-001 finding' ($Near.Count -eq 1)
Assert-Test 'Baseline has expected shared-counterparty finding' (
    $Shared.Count -eq 1 -and $Shared[0].TransactionCount -eq 2
)

# Test 2: Exactly at the exclusive upper amount boundary must not qualify.
$Boundary = @(
    (New-TestTransaction 'B-1' '2026-10-20T09:00:00Z' 'S-A' 'R-1' '9500'),
    (New-TestTransaction 'B-2' '2026-10-20T10:00:00Z' 'S-A' 'R-2' '9700'),
    (New-TestTransaction 'B-3' '2026-10-20T11:00:00Z' 'S-A' 'R-3' '10000')
)

$BoundaryFindings = @(
    Invoke-FraudLensDetection -Transactions $Boundary
)
Assert-Test 'Upper amount boundary is exclusive' (
    @($BoundaryFindings | Where-Object { $_.RuleId -eq 'FL-001' }).Count -eq 0
)

# Test 3: Minimum amount is inclusive.
$MinimumBoundary = @(
    (New-TestTransaction 'M-1' '2026-10-20T09:00:00Z' 'S-B' 'R-1' '9000'),
    (New-TestTransaction 'M-2' '2026-10-20T10:00:00Z' 'S-B' 'R-2' '9500'),
    (New-TestTransaction 'M-3' '2026-10-20T11:00:00Z' 'S-B' 'R-3' '9999')
)

$MinimumFindings = @(
    Invoke-FraudLensDetection -Transactions $MinimumBoundary
)
Assert-Test 'Minimum amount boundary is inclusive' (
    @($MinimumFindings | Where-Object { $_.RuleId -eq 'FL-001' }).Count -eq 1
)

# Test 4: Three transactions spread beyond the 24-hour window.
$OutsideWindow = @(
    (New-TestTransaction 'W-1' '2026-10-20T09:00:00Z' 'S-C' 'R-1' '9500'),
    (New-TestTransaction 'W-2' '2026-10-21T10:00:00Z' 'S-C' 'R-2' '9600'),
    (New-TestTransaction 'W-3' '2026-10-22T11:00:00Z' 'S-C' 'R-3' '9700')
)

$WindowFindings = @(
    Invoke-FraudLensDetection -Transactions $OutsideWindow
)
Assert-Test 'Transactions outside time window do not qualify' (
    @($WindowFindings | Where-Object { $_.RuleId -eq 'FL-001' }).Count -eq 0
)

# Test 5: Multiple transactions from the same sender are not
# multiple distinct senders for FL-002.
$SameSender = @(
    (New-TestTransaction 'S-1' '2026-10-20T09:00:00Z' 'SAME' 'COMMON' '100'),
    (New-TestTransaction 'S-2' '2026-10-20T10:00:00Z' 'SAME' 'COMMON' '200')
)

$SameSenderFindings = @(
    Invoke-FraudLensDetection -Transactions $SameSender
)
Assert-Test 'Same sender alone does not trigger FL-002' (
    @(
        $SameSenderFindings | Where-Object {
            $_.RuleId -eq 'FL-002' -and $_.ReceiverAccountId -eq 'COMMON'
        }
    ).Count -eq 0
)

# Test 6: Invalid input must be rejected before analysis.
$InvalidBatch = @(
    (New-TestTransaction 'DUP' '2026-10-20T09:00:00Z' 'S-D' 'R-D1' '100'),
    (New-TestTransaction 'DUP' '2026-10-20T10:00:00Z' 'S-E' 'R-D2' '200')
)

$InvalidRejected = $false
try {
    $null = Invoke-FraudLensDetection -Transactions $InvalidBatch
}
catch {
    $InvalidRejected = $true
}

Assert-Test 'Duplicate-ID batch is rejected' $InvalidRejected

# Test 7: Finding evidence contains source transaction IDs.
if ($Near.Count -eq 1) {
    $Evidence = @($Near[0].TransactionIds | Sort-Object)
    $Expected = @('SYN-1001', 'SYN-1002', 'SYN-1003')
    $EvidenceMatches = (@(Compare-Object $Expected $Evidence).Count -eq 0)
}
else {
    $EvidenceMatches = $false
}

Assert-Test 'FL-001 evidence IDs match expected records' $EvidenceMatches

# Test 8: Overlapping FL-001 and FL-002 patterns.
$OverlapTransactions = @(
    (New-TestTransaction 'OV-1' '2026-10-20T09:00:00Z' 'S-OVER-A' 'R-SHARED' '9500'),
    (New-TestTransaction 'OV-2' '2026-10-20T10:00:00Z' 'S-OVER-A' 'R-SHARED' '9600'),
    (New-TestTransaction 'OV-3' '2026-10-20T11:00:00Z' 'S-OVER-A' 'R-OTHER' '9700'),
    (New-TestTransaction 'OV-4' '2026-10-20T11:30:00Z' 'S-OVER-B' 'R-SHARED' '100')
)

$OverlapFindings = @(
    Invoke-FraudLensDetection -Transactions $OverlapTransactions
)

$OverlapFL001 = @(
    $OverlapFindings | Where-Object { $_.RuleId -eq 'FL-001' }
)

$OverlapFL002 = @(
    $OverlapFindings | Where-Object {
        $_.RuleId -eq 'FL-002' -and
        $_.ReceiverAccountId -eq 'R-SHARED'
    }
)

Assert-Test 'Overlap produces exactly one FL-001 finding' (
    $OverlapFL001.Count -eq 1
)

Assert-Test 'Overlap produces exactly one FL-002 finding' (
    $OverlapFL002.Count -eq 1
)

Assert-Test 'FL-001 retains all three qualifying transactions' (
    $OverlapFL001.Count -eq 1 -and
    $OverlapFL001[0].TransactionCount -eq 3 -and
    (@(Compare-Object @('OV-1','OV-2','OV-3') @($OverlapFL001[0].TransactionIds)).Count -eq 0)
)

Assert-Test 'FL-002 retains all three shared-receiver transactions' (
    $OverlapFL002.Count -eq 1 -and
    $OverlapFL002[0].TransactionCount -eq 3 -and
    $OverlapFL002[0].DistinctSenderCount -eq 2 -and
    (@(Compare-Object @('OV-1','OV-2','OV-4') @($OverlapFL002[0].TransactionIds)).Count -eq 0)
)

$OverlapEvidence = @(
    $OverlapFL001[0].TransactionIds |
        Where-Object { $OverlapFL002[0].TransactionIds -contains $_ }
)

Assert-Test 'Shared transactions appear in both findings' (
    (@(Compare-Object @('OV-1','OV-2') $OverlapEvidence).Count -eq 0)
)

$UniqueFindingIds = @(
    $OverlapFindings | Select-Object -ExpandProperty FindingId -Unique
)

Assert-Test 'Overlapping findings retain distinct finding IDs' (
    $UniqueFindingIds.Count -eq 2 -and $OverlapFindings.Count -eq 2
)

Write-Host "`n--- OVERLAPPING PATTERN TESTS COMPLETE ---" -ForegroundColor Cyan

Write-Host "`n=== Regression Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $script:Passed"
Write-Host "Failed: $script:Failed"

if ($script:Failed -gt 0) {
    throw "Regression suite failed: $script:Failed test(s)."
}

Write-Host 'ALL REGRESSION TESTS PASSED' -ForegroundColor Green
