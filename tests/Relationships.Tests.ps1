$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:USERPROFILE 'Documents\FraudLensAML'
$ModulePath = Join-Path $Root 'src\Analysis\FraudLensRelationships.psm1'

if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
    throw "Relationship module not found: $ModulePath"
}

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

function New-RelationshipTestTransaction {
    param(
        [string]$Id,
        [string]$Time,
        [string]$Sender,
        [string]$Receiver,
        [string]$Amount,
        [string]$Currency = 'USD'
    )

    [pscustomobject]@{
        TransactionId = $Id
        TimestampUtc = $Time
        SenderAccountId = $Sender
        ReceiverAccountId = $Receiver
        Amount = $Amount
        Currency = $Currency
        Channel = 'Wire'
    }
}

# Test 1: Unique account nodes.
$Transactions = @(
    (New-RelationshipTestTransaction 'R-001' '2026-10-20T09:00:00Z' 'A' 'B' '100'),
    (New-RelationshipTestTransaction 'R-002' '2026-10-20T10:00:00Z' 'A' 'C' '200'),
    (New-RelationshipTestTransaction 'R-003' '2026-10-20T11:00:00Z' 'B' 'C' '300')
)

$Graph = New-FraudLensRelationshipGraph -Transactions $Transactions

Assert-Test 'Three unique accounts produce three nodes' (
    $Graph.Nodes.Count -eq 3
)

# Test 2: Relationships preserve direction.
$AB = @(
    $Graph.Edges | Where-Object {
        $_.SenderAccountId -eq 'A' -and
        $_.ReceiverAccountId -eq 'B'
    }
)

Assert-Test 'Sender-to-receiver direction is preserved' (
    $AB.Count -eq 1
)

# Test 3: Repeated transactions aggregate correctly.
$Repeated = @(
    (New-RelationshipTestTransaction 'R-010' '2026-10-20T09:00:00Z' 'A' 'B' '100'),
    (New-RelationshipTestTransaction 'R-011' '2026-10-20T10:00:00Z' 'A' 'B' '250')
)

$RepeatedGraph = New-FraudLensRelationshipGraph -Transactions $Repeated
$RepeatedEdge = @($RepeatedGraph.Edges)[0]

Assert-Test 'Repeated account relationships aggregate to one edge' (
    $RepeatedGraph.Edges.Count -eq 1
)

Assert-Test 'Edge transaction count is correct' (
    $RepeatedEdge.TransactionCount -eq 2
)

Assert-Test 'Edge total amount is correct' (
    $RepeatedEdge.TotalAmount -eq [decimal]350
)

# Test 4: Different currencies remain separate.
$CurrencyTransactions = @(
    (New-RelationshipTestTransaction 'R-020' '2026-10-20T09:00:00Z' 'A' 'B' '100' 'USD'),
    (New-RelationshipTestTransaction 'R-021' '2026-10-20T10:00:00Z' 'A' 'B' '100' 'EUR')
)

$CurrencyGraph = New-FraudLensRelationshipGraph -Transactions $CurrencyTransactions

Assert-Test 'Different currencies produce separate edges' (
    $CurrencyGraph.Edges.Count -eq 2
)

# Test 5: Evidence IDs remain traceable.
$Evidence = @($RepeatedEdge.TransactionIds | Sort-Object)

Assert-Test 'Edge retains all supporting transaction IDs' (
    (@(Compare-Object @('R-010','R-011') $Evidence).Count -eq 0)
)

# Test 6: Node connection counts are correct.
$NodeA = @(
    $Graph.Nodes | Where-Object { $_.AccountId -eq 'A' }
)

Assert-Test 'Node outgoing connection count is correct' (
    $NodeA.Count -eq 1 -and $NodeA[0].OutDegree -eq 2
)

# Test 7: Invalid transaction batches are rejected.
$InvalidTransactions = @(
    (New-RelationshipTestTransaction 'DUP' '2026-10-20T09:00:00Z' 'A' 'B' '100'),
    (New-RelationshipTestTransaction 'DUP' '2026-10-20T10:00:00Z' 'B' 'C' '200')
)

$InvalidRejected = $false

try {
    $null = New-FraudLensRelationshipGraph -Transactions $InvalidTransactions
}
catch {
    $InvalidRejected = $true
}

Assert-Test 'Invalid transaction batches are rejected' $InvalidRejected

# Test 8: Connected components group indirectly connected accounts.
$ComponentTransactions = @(
    (New-RelationshipTestTransaction 'C-001' '2026-10-20T09:00:00Z' 'A' 'B' '100'),
    (New-RelationshipTestTransaction 'C-002' '2026-10-20T10:00:00Z' 'B' 'C' '200'),
    (New-RelationshipTestTransaction 'C-003' '2026-10-20T11:00:00Z' 'X' 'Y' '300')
)

$ComponentGraph = New-FraudLensRelationshipGraph -Transactions $ComponentTransactions

Assert-Test 'Connected component output exists' (
    $null -ne $ComponentGraph.Components
)

Assert-Test 'Two disconnected networks produce two components' (
    $ComponentGraph.Components.Count -eq 2
)

$LargeComponent = @(
    $ComponentGraph.Components | Where-Object {
        $_.AccountIds -contains 'A'
    }
)

Assert-Test 'Indirectly connected A, B, and C belong together' (
    $LargeComponent.Count -eq 1 -and
    $LargeComponent[0].AccountCount -eq 3 -and
    (@(Compare-Object @('A','B','C') @($LargeComponent[0].AccountIds)).Count -eq 0)
)

$SmallComponent = @(
    $ComponentGraph.Components | Where-Object {
        $_.AccountIds -contains 'X'
    }
)

Assert-Test 'Unrelated X and Y remain in a separate component' (
    $SmallComponent.Count -eq 1 -and
    $SmallComponent[0].AccountCount -eq 2 -and
    (@(Compare-Object @('X','Y') @($SmallComponent[0].AccountIds)).Count -eq 0)
)

Assert-Test 'Component evidence retains all supporting transaction IDs' (
    $LargeComponent.Count -eq 1 -and
    (@(Compare-Object @('C-001','C-002') @($LargeComponent[0].TransactionIds)).Count -eq 0)
)

Write-Host "`n--- CONNECTED COMPONENT TESTS COMPLETE ---" -ForegroundColor Cyan

# Test 13: Directed multi-hop path discovery.
$PathTransactions = @(
    (New-RelationshipTestTransaction 'P-001' '2026-10-20T09:00:00Z' 'A' 'B' '100'),
    (New-RelationshipTestTransaction 'P-002' '2026-10-20T10:00:00Z' 'B' 'C' '200'),
    (New-RelationshipTestTransaction 'P-003' '2026-10-20T11:00:00Z' 'A' 'D' '300'),
    (New-RelationshipTestTransaction 'P-004' '2026-10-20T12:00:00Z' 'D' 'C' '400')
)

$PathGraph = New-FraudLensRelationshipGraph -Transactions $PathTransactions

$Paths = @(
    Find-FraudLensRelationshipPaths `
        -Graph $PathGraph `
        -SourceAccountId 'A' `
        -TargetAccountId 'C' `
        -MaxHops 2
)

Assert-Test 'Two valid two-hop paths are discovered' (
    $Paths.Count -eq 2
)

Assert-Test 'Path discovery returns the expected account sequences' (
    $Paths.Count -eq 2 -and
    (@($Paths | Where-Object {
        (@($_.AccountIds) -join '->') -eq 'A->B->C'
    }).Count -eq 1) -and
    (@($Paths | Where-Object {
        (@($_.AccountIds) -join '->') -eq 'A->D->C'
    }).Count -eq 1)
)

# Test 14: Maximum hop limit is respected.
$LimitedPaths = @(
    Find-FraudLensRelationshipPaths `
        -Graph $PathGraph `
        -SourceAccountId 'A' `
        -TargetAccountId 'C' `
        -MaxHops 1
)

Assert-Test 'Maximum hop limit excludes longer paths' (
    $LimitedPaths.Count -eq 0
)

# Test 15: Path evidence preserves transaction IDs.
$PathWithEvidence = @(
    $Paths | Where-Object {
        (@($_.AccountIds) -join '->') -eq 'A->B->C'
    }
)

Assert-Test 'Multi-hop path retains evidence for every hop' (
    $PathWithEvidence.Count -eq 1 -and
    (@(Compare-Object @('P-001','P-002') @($PathWithEvidence[0].TransactionIds)).Count -eq 0)
)

# Test 16: Paths follow transaction direction.
$ReversePaths = @(
    Find-FraudLensRelationshipPaths `
        -Graph $PathGraph `
        -SourceAccountId 'C' `
        -TargetAccountId 'A' `
        -MaxHops 3
)

Assert-Test 'Reverse path is not invented without reverse transactions' (
    $ReversePaths.Count -eq 0
)

# Test 17: Cycles do not repeat accounts within a path.
$CycleTransactions = @(
    (New-RelationshipTestTransaction 'CY-001' '2026-10-20T09:00:00Z' 'A' 'B' '100'),
    (New-RelationshipTestTransaction 'CY-002' '2026-10-20T10:00:00Z' 'B' 'A' '100'),
    (New-RelationshipTestTransaction 'CY-003' '2026-10-20T11:00:00Z' 'B' 'C' '100')
)

$CycleGraph = New-FraudLensRelationshipGraph -Transactions $CycleTransactions

$CyclePaths = @(
    Find-FraudLensRelationshipPaths `
        -Graph $CycleGraph `
        -SourceAccountId 'A' `
        -TargetAccountId 'C' `
        -MaxHops 3
)

$NoRepeatedAccounts = $true

foreach ($Path in $CyclePaths) {
    if (@($Path.AccountIds | Select-Object -Unique).Count -ne $Path.AccountIds.Count) {
        $NoRepeatedAccounts = $false
    }
}

Assert-Test 'Path traversal does not repeat accounts' (
    $CyclePaths.Count -eq 1 -and $NoRepeatedAccounts
)

Write-Host "`n--- MULTI-HOP PATH TESTS COMPLETE ---" -ForegroundColor Cyan

# Test 18: Potential pass-through activity.
$PassThroughTransactions = @(
    (New-RelationshipTestTransaction 'PT-001' '2026-10-20T09:00:00Z' 'SENDER-A' 'INTERMEDIARY-B' '1000' 'USD'),
    (New-RelationshipTestTransaction 'PT-002' '2026-10-20T15:00:00Z' 'INTERMEDIARY-B' 'RECEIVER-C' '950' 'USD')
)

$PassThroughResults = @(
    Find-FraudLensPassThroughActivity `
        -Transactions $PassThroughTransactions `
        -MaxElapsedHours 24 `
        -AmountTolerancePercent 10
)

Assert-Test 'Qualifying incoming and outgoing transactions produce a candidate' (
    $PassThroughResults.Count -eq 1
)

Assert-Test 'Candidate identifies the intermediary account' (
    $PassThroughResults.Count -eq 1 -and
    $PassThroughResults[0].AccountId -eq 'INTERMEDIARY-B'
)

Assert-Test 'Candidate preserves both transaction IDs' (
    $PassThroughResults.Count -eq 1 -and
    $PassThroughResults[0].IncomingTransactionId -eq 'PT-001' -and
    $PassThroughResults[0].OutgoingTransactionId -eq 'PT-002'
)

# Test 19: Activity outside the time window.
$LateTransactions = @(
    (New-RelationshipTestTransaction 'PT-010' '2026-10-20T09:00:00Z' 'A' 'B' '1000'),
    (New-RelationshipTestTransaction 'PT-011' '2026-10-21T10:00:00Z' 'B' 'C' '1000')
)

$LateResults = @(
    Find-FraudLensPassThroughActivity -Transactions $LateTransactions -MaxElapsedHours 24 -AmountTolerancePercent 10
)

Assert-Test 'Outgoing activity outside the time window is excluded' (
    $LateResults.Count -eq 0
)

# Test 20: Amount difference exceeds tolerance.
$AmountTransactions = @(
    (New-RelationshipTestTransaction 'PT-020' '2026-10-20T09:00:00Z' 'A' 'B' '1000'),
    (New-RelationshipTestTransaction 'PT-021' '2026-10-20T10:00:00Z' 'B' 'C' '700')
)

$AmountResults = @(
    Find-FraudLensPassThroughActivity -Transactions $AmountTransactions -MaxElapsedHours 24 -AmountTolerancePercent 10
)

Assert-Test 'Outgoing amount outside tolerance is excluded' (
    $AmountResults.Count -eq 0
)

# Test 21: Currency must match.
$CurrencyPassThrough = @(
    (New-RelationshipTestTransaction 'PT-030' '2026-10-20T09:00:00Z' 'A' 'B' '1000' 'USD'),
    (New-RelationshipTestTransaction 'PT-031' '2026-10-20T10:00:00Z' 'B' 'C' '1000' 'EUR')
)

$CurrencyResults = @(
    Find-FraudLensPassThroughActivity -Transactions $CurrencyPassThrough -MaxElapsedHours 24 -AmountTolerancePercent 10
)

Assert-Test 'Different currencies are not matched' (
    $CurrencyResults.Count -eq 0
)

# Test 22: Outgoing transaction must occur after incoming transaction.
$ReverseTimeTransactions = @(
    (New-RelationshipTestTransaction 'PT-040' '2026-10-20T12:00:00Z' 'A' 'B' '1000'),
    (New-RelationshipTestTransaction 'PT-041' '2026-10-20T09:00:00Z' 'B' 'C' '1000')
)

$ReverseTimeResults = @(
    Find-FraudLensPassThroughActivity -Transactions $ReverseTimeTransactions -MaxElapsedHours 24 -AmountTolerancePercent 10
)

Assert-Test 'Outgoing transaction before incoming transaction is excluded' (
    $ReverseTimeResults.Count -eq 0
)

# Test 23: Same counterparty is not treated as intermediary movement.
$SameCounterpartyTransactions = @(
    (New-RelationshipTestTransaction 'PT-050' '2026-10-20T09:00:00Z' 'A' 'B' '1000'),
    (New-RelationshipTestTransaction 'PT-051' '2026-10-20T10:00:00Z' 'B' 'A' '1000')
)

$SameCounterpartyResults = @(
    Find-FraudLensPassThroughActivity -Transactions $SameCounterpartyTransactions -MaxElapsedHours 24 -AmountTolerancePercent 10
)

Assert-Test 'Return to the original counterparty is excluded' (
    $SameCounterpartyResults.Count -eq 0
)

# Test 24: Invalid input must be rejected.
$InvalidPassThroughTransactions = @(
    (New-RelationshipTestTransaction 'PT-DUP' '2026-10-20T09:00:00Z' 'A' 'B' '100'),
    (New-RelationshipTestTransaction 'PT-DUP' '2026-10-20T10:00:00Z' 'B' 'C' '100')
)

$PassThroughInvalidRejected = $false

try {
    $null = Find-FraudLensPassThroughActivity -Transactions $InvalidPassThroughTransactions
}
catch {
    $PassThroughInvalidRejected = $true
}

Assert-Test 'Invalid pass-through transaction batch is rejected' $PassThroughInvalidRejected

Write-Host "`n--- PASS-THROUGH ACTIVITY TESTS COMPLETE ---" -ForegroundColor Cyan

Write-Host "`n=== RELATIONSHIP TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Passed: $script:Passed"
Write-Host "Failed: $script:Failed"

if ($script:Failed -gt 0) {
    throw "Relationship tests failed: $script:Failed test(s)."
}

Write-Host 'ALL RELATIONSHIP TESTS PASSED' -ForegroundColor Green

# Test 25: Composite edge keys must not collide when identifiers contain pipes.
$CollisionTransactions = @(
    (New-RelationshipTestTransaction 'KEY-001' '2026-10-20T09:00:00Z' 'A|B' 'C' '100' 'USD'),
    (New-RelationshipTestTransaction 'KEY-002' '2026-10-20T10:00:00Z' 'A' 'B|C' '200' 'USD')
)

$CollisionGraph = New-FraudLensRelationshipGraph -Transactions $CollisionTransactions

Assert-Test 'Pipe characters in account IDs do not merge distinct edges' (
    $CollisionGraph.Edges.Count -eq 2
)

Write-Host "`n--- EDGE KEY COLLISION TEST COMPLETE ---" -ForegroundColor Cyan

# Test 26: Multi-currency path evidence remains separated by currency.
$MixedCurrencyPathTransactions = @(
    (New-RelationshipTestTransaction 'MC-001' '2026-10-20T09:00:00Z' 'A' 'B' '100' 'USD'),
    (New-RelationshipTestTransaction 'MC-002' '2026-10-20T09:05:00Z' 'A' 'B' '100' 'EUR'),
    (New-RelationshipTestTransaction 'MC-003' '2026-10-20T10:00:00Z' 'B' 'C' '200' 'EUR')
)

$MixedCurrencyGraph = New-FraudLensRelationshipGraph -Transactions $MixedCurrencyPathTransactions

$MixedCurrencyPaths = @(
    Find-FraudLensRelationshipPaths `
        -Graph $MixedCurrencyGraph `
        -SourceAccountId 'A' `
        -TargetAccountId 'C' `
        -MaxHops 2
)

$FirstHopCurrencyEvidence = @(
    $MixedCurrencyPaths[0].HopEvidence[0].CurrencyEvidence
)

Assert-Test 'Multi-currency path is discovered' (
    $MixedCurrencyPaths.Count -eq 1
)

Assert-Test 'First hop preserves separate USD and EUR evidence' (
    $FirstHopCurrencyEvidence.Count -eq 2
)

$UsdEvidence = @(
    $FirstHopCurrencyEvidence | Where-Object { $_.Currency -eq 'USD' }
)

$EurEvidence = @(
    $FirstHopCurrencyEvidence | Where-Object { $_.Currency -eq 'EUR' }
)

Assert-Test 'USD evidence retains only its supporting transaction ID' (
    $UsdEvidence.Count -eq 1 -and
    (@($UsdEvidence[0].TransactionIds) -join ',') -eq 'MC-001'
)

Assert-Test 'EUR evidence retains only its supporting transaction ID' (
    $EurEvidence.Count -eq 1 -and
    (@($EurEvidence[0].TransactionIds) -join ',') -eq 'MC-002'
)

Assert-Test 'Second hop retains its EUR currency evidence' (
    $MixedCurrencyPaths.Count -eq 1 -and
    $MixedCurrencyPaths[0].HopEvidence[1].CurrencyEvidence.Count -eq 1 -and
    $MixedCurrencyPaths[0].HopEvidence[1].CurrencyEvidence[0].Currency -eq 'EUR'
)

Write-Host "`n--- MULTI-CURRENCY PATH EVIDENCE TESTS COMPLETE ---" -ForegroundColor Cyan