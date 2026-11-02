$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:USERPROFILE 'Documents\FraudLensAML'
$ValidationPath = Join-Path $Root 'src\Core\TransactionValidation.psm1'
$DetectionPath = Join-Path $Root 'src\Detection\FraudLensDetection.psm1'

Import-Module $ValidationPath -Force
Import-Module $DetectionPath -Force

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

function New-ValidTransaction {
    param(
        [string]$Id = 'VAL-001',
        [string]$Timestamp = '2026-10-20T09:00:00Z',
        [string]$Sender = 'SENDER-1',
        [string]$Receiver = 'RECEIVER-1',
        [string]$Amount = '100.00'
    )

    [pscustomobject]@{
        TransactionId   = $Id
        TimestampUtc    = $Timestamp
        SenderAccountId = $Sender
        ReceiverAccountId = $Receiver
        Amount          = $Amount
        Currency        = 'USD'
        Channel         = 'Wire'
    }
}

function Test-TransactionRejected {
    param(
        [object]$Transaction
    )

    $Result = @(Test-FraudLensTransactions -Transactions @($Transaction))
    return ($Result.Count -eq 1 -and -not $Result[0].IsValid)
}

# 1. Valid transaction is accepted.
$Valid = New-ValidTransaction
$ValidResult = @(Test-FraudLensTransactions -Transactions @($Valid))

Assert-Test 'Valid transaction is accepted' (
    $ValidResult.Count -eq 1 -and $ValidResult[0].IsValid
)

# 2. Missing required field.
$MissingField = New-ValidTransaction
$MissingField.PSObject.Properties.Remove('Currency')

Assert-Test 'Missing required field is rejected' (
    Test-TransactionRejected -Transaction $MissingField
)

# 3. Blank transaction ID.
$BlankId = New-ValidTransaction -Id ' '
Assert-Test 'Blank transaction ID is rejected' (
    Test-TransactionRejected -Transaction $BlankId
)

# 4. Invalid timestamp.
$BadTimestamp = New-ValidTransaction -Timestamp 'not-a-date'
Assert-Test 'Invalid timestamp is rejected' (
    Test-TransactionRejected -Transaction $BadTimestamp
)

# 5. Invalid amount text.
$BadAmount = New-ValidTransaction -Amount 'not-a-number'
Assert-Test 'Non-numeric amount is rejected' (
    Test-TransactionRejected -Transaction $BadAmount
)

# 6. Zero amount.
$ZeroAmount = New-ValidTransaction -Amount '0'
Assert-Test 'Zero amount is rejected' (
    Test-TransactionRejected -Transaction $ZeroAmount
)

# 7. Negative amount.
$NegativeAmount = New-ValidTransaction -Amount '-25'
Assert-Test 'Negative amount is rejected' (
    Test-TransactionRejected -Transaction $NegativeAmount
)

# 8. Blank sender account.
$BlankSender = New-ValidTransaction -Sender ' '
Assert-Test 'Blank sender account is rejected' (
    Test-TransactionRejected -Transaction $BlankSender
)

# 9. Blank receiver account.
$BlankReceiver = New-ValidTransaction -Receiver ' '
Assert-Test 'Blank receiver account is rejected' (
    Test-TransactionRejected -Transaction $BlankReceiver
)

# 10. Sender and receiver cannot be identical.
$SameAccount = New-ValidTransaction -Sender 'SAME-ACCOUNT' -Receiver 'SAME-ACCOUNT'
Assert-Test 'Identical sender and receiver are rejected' (
    Test-TransactionRejected -Transaction $SameAccount
)

# 11. Detection must reject invalid input before producing findings.
$DetectionRejected = $false

try {
    $Invalid = New-ValidTransaction -Amount 'invalid'
    $null = Invoke-FraudLensDetection -Transactions @($Invalid)
}
catch {
    $DetectionRejected = $_.Exception.Message -like '*Input rejected*'
}

Assert-Test 'Detection rejects invalid input before analysis' $DetectionRejected

Write-Host "`n=== Validation Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $script:Passed"
Write-Host "Failed: $script:Failed"

if ($script:Failed -gt 0) {
    throw "Validation suite failed: $script:Failed test(s)."
}

Write-Host 'ALL VALIDATION TESTS PASSED' -ForegroundColor Green
