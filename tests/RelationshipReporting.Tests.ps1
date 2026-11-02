$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$ReportingModule = Join-Path $Root 'src\Reporting\FraudLensRelationshipReporting.psm1'
$RelationshipsModule = Join-Path $Root 'src\Analysis\FraudLensRelationships.psm1'

Import-Module $RelationshipsModule -Force
Import-Module $ReportingModule -Force

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

function New-ReportingTestTransaction {
    param(
        [string]$Id,
        [string]$Sender,
        [string]$Receiver,
        [double]$Amount,
        [string]$Timestamp
    )

    [pscustomobject]@{
        TransactionId  = $Id
        TimestampUtc   = $Timestamp
        SenderAccountId = $Sender
        ReceiverAccountId = $Receiver
        Amount         = $Amount
        Currency       = 'USD'
        Channel        = 'Wire'
    }
}

$Transactions = @(
    (New-ReportingTestTransaction 'RP-001' 'A' 'B' 1000 '2026-01-01T08:00:00Z')
    (New-ReportingTestTransaction 'RP-002' 'B' 'C' 950  '2026-01-01T09:00:00Z')
    (New-ReportingTestTransaction 'RP-003' 'C' 'D' 900  '2026-01-01T10:00:00Z')
    (New-ReportingTestTransaction 'RP-004' 'X' 'Y' 200  '2026-01-01T11:00:00Z')
)

$Graph = New-FraudLensRelationshipGraph -Transactions $Transactions

$PassThrough = @(
    Find-FraudLensPassThroughActivity `
        -Transactions $Transactions `
        -MaxElapsedHours 24 `
        -AmountTolerancePercent 10
)

$Paths = @(
    Find-FraudLensRelationshipPaths `
        -Graph $Graph `
        -SourceAccountId 'A' `
        -TargetAccountId 'D' `
        -MaxHops 3
)

$ReportSection = New-FraudLensRelationshipReportSection `
    -Graph $Graph `
    -PassThroughCandidates $PassThrough `
    -Paths $Paths

Assert-Test 'Relationship report section is returned' (
    $null -ne $ReportSection
)

Assert-Test 'Graph summary preserves node count' (
    $ReportSection.Graph.NodeCount -eq $Graph.NodeCount
)

Assert-Test 'Graph summary preserves edge count' (
    $ReportSection.Graph.EdgeCount -eq $Graph.EdgeCount
)

Assert-Test 'Graph summary preserves connected components' (
    $ReportSection.Graph.ComponentCount -eq $Graph.ComponentCount
)

Assert-Test 'Graph edges preserve source transaction evidence' (
    $ReportSection.Graph.Edges.Count -eq $Graph.Edges.Count
)

Assert-Test 'Pass-through candidates are included' (
    $ReportSection.PassThroughCandidateCount -eq $PassThrough.Count
)

Assert-Test 'Pass-through evidence preserves transaction IDs' (
    $ReportSection.PassThroughCandidates[0].IncomingTransactionId -eq 'RP-001' -and
    $ReportSection.PassThroughCandidates[0].OutgoingTransactionId -eq 'RP-002'
)

Assert-Test 'Multi-hop paths are included when supplied' (
    $ReportSection.PathCount -eq $Paths.Count
)

Assert-Test 'Multi-hop path preserves transaction evidence' (
    $ReportSection.Paths[0].TransactionIds.Count -eq 3
)

Assert-Test 'Human review remains required' (
    $ReportSection.Safety.HumanReviewRequired -eq $true
)

Assert-Test 'Automated adverse decisions remain disabled' (
    $ReportSection.Safety.AutomatedAccountDecision -eq $false
)

$LimitationText = [string]::Join(
    ' ',
    [string[]]@($ReportSection.Limitations)
)

Assert-Test 'Report explicitly disclaims proof of misconduct' (
    $LimitationText.Contains('not proof of misconduct')
)

Write-Host ''
Write-Host '=== RELATIONSHIP REPORTING TEST SUMMARY ===' -ForegroundColor Cyan
Write-Host "Passed: $script:Passed"
Write-Host "Failed: $script:Failed"

if ($script:Failed -gt 0) {
    throw 'Relationship reporting tests failed.'
}
