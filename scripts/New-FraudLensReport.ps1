[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$CsvPath = Join-Path $Root 'data\synthetic\transactions.csv'
$ReportDir = Join-Path $Root 'reports'
$ValidationModule = Join-Path $Root 'src\Core\TransactionValidation.psm1'
$DetectionModule = Join-Path $Root 'src\Detection\FraudLensDetection.psm1'

foreach ($RequiredPath in @($CsvPath, $ValidationModule, $DetectionModule)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Required project file is missing: $RequiredPath"
    }
}

if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null
}

Import-Module $ValidationModule -Force
Import-Module $DetectionModule -Force
Import-Module (Join-Path $Root 'src\Reporting\FraudLensAnalystGuidance.psm1') -Force

$Transactions = @(Import-Csv -LiteralPath $CsvPath)
if ($Transactions.Count -eq 0) {
    throw 'The synthetic transaction CSV contains no records.'
}

$ValidationResults = @(Test-FraudLensTransactions -Transactions $Transactions)
$InvalidResults = @($ValidationResults | Where-Object { -not $_.IsValid })

if ($InvalidResults.Count -gt 0) {
    $Details = $InvalidResults | ForEach-Object {
        '{0}: {1}' -f $_.TransactionId, ($_.Errors -join '; ')
    }
    throw ("Validation failed. No report was generated.`n" + ($Details -join "`n"))
}

$Findings = @(Invoke-FraudLensDetection -Transactions $Transactions)

foreach ($Finding in $Findings) {
    $Finding | Add-Member -NotePropertyName AnalystGuidance -NotePropertyValue (Get-FraudLensAnalystGuidance -RuleId ([string]$Finding.RuleId)) -Force
}

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$JsonPath = Join-Path $ReportDir ("FraudLens-AML-{0}.json" -f $Timestamp)
$HtmlPath = Join-Path $ReportDir ("FraudLens-AML-{0}.html" -f $Timestamp)

$Report = [PSCustomObject]@{
    Project             = 'FraudLens AML'
    GeneratedAt         = (Get-Date).ToString('o')
    Dataset             = 'Synthetic demonstration data'
    SyntheticDataOnly   = $true
    TransactionCount    = $Transactions.Count
    ValidTransactionCount = $ValidationResults.Count
    InvalidTransactionCount = $InvalidResults.Count
    FindingCount        = $Findings.Count
    Findings            = @($Findings)
    Limitations         = @(
        'Demonstration uses synthetic data only.'
        'Rule alerts are leads for human review, not proof of wrongdoing.'
        'No SAR filing, account restriction, or automated adverse decision is performed.'
        'Rules have not been validated for production use.'
    )
}

$Report | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $JsonPath -Encoding UTF8

$Style = '<style>body{margin:0;padding:32px;background:#f3f6fa;color:#202b3c;font-family:Segoe UI,Arial,sans-serif;line-height:1.55}h1{color:#14263d;border-bottom:4px solid #36a6a0;padding-bottom:14px}h2{color:#1b456b;margin-top:30px}table{border-collapse:collapse;width:100%;margin:16px 0;background:white;table-layout:auto}th,td{border:1px solid #dce3ec;padding:11px 13px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#eaf0f6;color:#203c5a}tr:nth-child(even) td{background:#f8fafc}p,li{line-height:1.65}body>p{color:#52657c}@media(max-width:700px){body{padding:12px}th,td{padding:7px;font-size:13px}}</style>'

$FindingCards = @()

foreach ($Finding in $Findings) {
    $RuleId = [System.Net.WebUtility]::HtmlEncode([string]$Finding.RuleId)
    $FindingId = [System.Net.WebUtility]::HtmlEncode([string]$Finding.FindingId)
    $RuleName = [System.Net.WebUtility]::HtmlEncode([string]$Finding.RuleName)
    $Explanation = [System.Net.WebUtility]::HtmlEncode([string]$Finding.Explanation)

    $Sender = [System.Net.WebUtility]::HtmlEncode([string]$Finding.SenderAccountId)
    $Receiver = [System.Net.WebUtility]::HtmlEncode([string]$Finding.ReceiverAccountId)

    $TransactionIdList = @($Finding.TransactionIds | ForEach-Object {
        [string]$_
    }) -join ', '

    $TransactionIdList = [System.Net.WebUtility]::HtmlEncode($TransactionIdList)

    $TransactionCount = [System.Net.WebUtility]::HtmlEncode([string]$Finding.TransactionCount)
    $DistinctSenderCount = [System.Net.WebUtility]::HtmlEncode([string]$Finding.DistinctSenderCount)
    $WindowStart = [System.Net.WebUtility]::HtmlEncode([string]$Finding.WindowStartUtc)
    $WindowEnd = [System.Net.WebUtility]::HtmlEncode([string]$Finding.WindowEndUtc)
    $ReviewRequired = [System.Net.WebUtility]::HtmlEncode([string]$Finding.ReviewRequired)
    $Guidance = $Finding.AnalystGuidance
    $GuidanceHeading = [System.Net.WebUtility]::HtmlEncode([string]$Guidance.Heading)
    $GuidanceLimitation = [System.Net.WebUtility]::HtmlEncode([string]$Guidance.Limitation)
    $GuidanceStepsHtml = @($Guidance.ReviewSteps | ForEach-Object {
        '<li>{0}</li>' -f [System.Net.WebUtility]::HtmlEncode([string]$_)
    }) -join "`r`n"
    $AnalystGuidanceHtml = @(
        '<section class="analyst-guidance"><h4>Analyst review guidance</h4>'
        ('<p class="guidance-heading">{0}</p>' -f $GuidanceHeading)
        ('<ul>{0}</ul>' -f $GuidanceStepsHtml)
        ('<p class="guidance-limit"><strong>Limitation:</strong> {0}</p>' -f $GuidanceLimitation)
        '<p class="guidance-limit"><strong>Human review:</strong> Follow applicable internal procedures. This tool does not file SARs or make account decisions.</p>'
        '</section>'
    ) -join "`r`n"

    $Evidence = @(
        ('<div class="fact"><span>Finding ID</span><strong>{0}</strong></div>' -f $FindingId)
        ('<div class="fact"><span>Sender account</span><strong>{0}</strong></div>' -f $(if ($Sender) { $Sender } else { 'Not applicable' }))
        ('<div class="fact"><span>Receiving account</span><strong>{0}</strong></div>' -f $(if ($Receiver) { $Receiver } else { 'Not applicable' }))
        ('<div class="fact"><span>Transactions</span><strong>{0}</strong></div>' -f $(if ($TransactionCount) { $TransactionCount } else { 'Not specified' }))
        ('<div class="fact"><span>Distinct senders</span><strong>{0}</strong></div>' -f $(if ($DistinctSenderCount) { $DistinctSenderCount } else { 'Not specified' }))
        ('<div class="fact"><span>Review required</span><strong>{0}</strong></div>' -f $(if ($ReviewRequired) { $ReviewRequired } else { 'Not specified' }))
    )

    $Window = if ($WindowStart -or $WindowEnd) {
        '<div class="window"><span>Analysis window (UTC)</span><div>{0}</div><div>{1}</div></div>' -f `
            $(if ($WindowStart) { $WindowStart } else { 'Start not specified' }), `
            $(if ($WindowEnd) { $WindowEnd } else { 'End not specified' })
    } else {
        ''
    }

    $FindingCards += @"
<article class="finding-card">
  <div class="finding-top">
    <span class="rule-badge">$RuleId</span>
    <span class="finding-ref">$FindingId</span>
  </div>
  <h3>$RuleName</h3>
  <p class="explanation">$Explanation</p>
   $AnalystGuidanceHtml
  <h4>Evidence summary</h4>
  <div class="facts">
    $($Evidence -join "`r`n    ")
  </div>
  <div class="transaction-evidence">
    <span>Supporting transaction IDs</span>
    <p>$TransactionIdList</p>
  </div>
  $Window
</article>
"@
}

$FindingHtml = if ($FindingCards.Count -gt 0) {
    $FindingCards -join "`r`n"
}
else {
    '<div class="empty-state">No findings were produced by the configured demonstration rules.</div>'
}

$HtmlParts = @(
    '<!DOCTYPE html>'
    '<html><head><meta charset="utf-8">'
    '<title>FraudLens AML Report</title>'
    $Style
    '</head><body>'
    '<h1>FraudLens AML</h1>'
    '<p class="meta">Synthetic-data demonstration report</p>'
    ('<p><strong>Generated:</strong> {0}</p>' -f [System.Net.WebUtility]::HtmlEncode($Report.GeneratedAt))
    '<h2>Summary</h2>'
    '<table><tr><th>Metric</th><th>Value</th></tr>'
    ('<tr><td>Transactions</td><td>{0}</td></tr>' -f $Report.TransactionCount)
    ('<tr><td>Valid records</td><td>{0}</td></tr>' -f $Report.ValidTransactionCount)
    ('<tr><td>Invalid records</td><td>{0}</td></tr>' -f $Report.InvalidTransactionCount)
    ('<tr><td>Findings</td><td>{0}</td></tr>' -f $Report.FindingCount)
    '</table>'
    '<h2>Detection findings</h2>'
    $FindingHtml
    '<h2>Important limitations</h2>'
    '<div class="note"><ul>'
)

foreach ($Limitation in $Report.Limitations) {
    $HtmlParts += '<li>{0}</li>' -f [System.Net.WebUtility]::HtmlEncode($Limitation)
}

$HtmlParts += @('</ul></div>', '</body></html>')
$Html = $HtmlParts -join "`r`n"
$CssOverride = 'body{box-sizing:border-box;max-width:1120px;margin:0 auto;padding:30px;background:#f3f6fa;color:#243449;font-family:"Segoe UI",Arial,sans-serif;font-size:13px;line-height:1.5}
h1{font-size:27px;color:#142a43;border-bottom:3px solid #278b86;padding-bottom:13px}
h2{font-size:19px;color:#204665;margin:30px 0 14px}
h3{font-size:17px;line-height:1.35;color:#1a3450;margin:13px 0 8px}
h4{font-size:12px;text-transform:uppercase;letter-spacing:.7px;color:#5c6f83;margin:22px 0 10px}
table{width:100%;border-collapse:collapse;table-layout:auto;font-size:12px;margin:14px 0;background:#fff}
th,td{padding:10px 12px;border:1px solid #dce4ed;text-align:left;vertical-align:top;overflow-wrap:anywhere}
th{background:#e8eef5;color:#344b63;font-weight:600}
tr:nth-child(even) td{background:#f8fafc}
.finding-card{background:#fff;border:1px solid #dbe4ed;border-radius:10px;padding:22px;margin:16px 0 20px;box-shadow:0 3px 10px rgba(20,42,67,.05);break-inside:avoid}
.finding-top{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap}
.rule-badge{display:inline-block;background:#e1f2f0;color:#176d68;border-radius:5px;padding:4px 9px;font-size:11px;font-weight:700;letter-spacing:.4px}
.finding-ref{font-size:11px;color:#718096;overflow-wrap:anywhere}
.explanation{font-size:13px;color:#52657a;margin:7px 0 16px}
.facts{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
.fact{background:#f6f8fb;border:1px solid #e5ebf2;border-radius:6px;padding:10px 12px;min-width:0}
.fact span,.transaction-evidence span,.window span{display:block;color:#697a8d;font-size:11px;text-transform:uppercase;letter-spacing:.45px;margin-bottom:4px}
.fact strong{display:block;font-size:13px;font-weight:600;color:#243b53;overflow-wrap:anywhere}
.transaction-evidence{margin-top:12px;padding:12px 14px;background:#edf5f5;border-left:3px solid #278b86;border-radius:4px}
.transaction-evidence p{margin:4px 0 0;font-family:Consolas,monospace;font-size:12px;line-height:1.8;overflow-wrap:anywhere;color:#254b56}
.window{margin-top:12px;padding:12px 14px;background:#f8fafc;border:1px solid #e5ebf2;border-radius:5px;overflow-wrap:anywhere}
.window div{font-size:12px;color:#344b63}
.note{background:#edf5f5;border-left:4px solid #278b86;padding:14px 18px;border-radius:4px}
.meta{font-size:12px;color:#65758a}
.empty-state{padding:20px;background:#fff;border:1px solid #dce4ed;border-radius:8px;color:#52657a}
@media(max-width:650px){body{padding:14px}.facts{grid-template-columns:minmax(0,1fr)}.finding-card{padding:15px}table{font-size:11px}th,td{padding:7px}}'
$Html = $Html.Replace('</style>', ($CssOverride + '</style>'))
# Build expandable evidence from the synthetic source transactions.
$FraudLensEvidenceSection = '<section class="section evidence-section"><h2>Supporting Transaction Evidence</h2><p class="meta">Each panel links a detection finding to the source transactions used by the rule.</p>'

$FraudLensTransactionLookup = @{}
foreach ($FraudLensTx in $Transactions) {
    $FraudLensTransactionLookup[[string]$FraudLensTx.TransactionId] = $FraudLensTx
}

foreach ($FraudLensFinding in $Findings) {
    $FraudLensSafeId = [System.Net.WebUtility]::HtmlEncode([string]$FraudLensFinding.FindingId)
    $FraudLensSafeRule = [System.Net.WebUtility]::HtmlEncode([string]$FraudLensFinding.RuleId)
    $FraudLensSafeName = [System.Net.WebUtility]::HtmlEncode([string]$FraudLensFinding.RuleName)
    $FraudLensRows = @()
    $FraudLensMatched = 0

    foreach ($FraudLensId in @($FraudLensFinding.TransactionIds)) {
        $FraudLensKey = [string]$FraudLensId

        if (-not $FraudLensTransactionLookup.ContainsKey($FraudLensKey)) {
            $FraudLensRows += '<tr><td>{0}</td><td colspan="6">Transaction not found in source dataset</td></tr>' -f [System.Net.WebUtility]::HtmlEncode($FraudLensKey)
            continue
        }

        $FraudLensRecord = $FraudLensTransactionLookup[$FraudLensKey]
        $FraudLensMatched++

        $FraudLensCells = @(
            $FraudLensRecord.TransactionId
            $FraudLensRecord.TimestampUtc
            $FraudLensRecord.Amount
            $FraudLensRecord.Currency
            $FraudLensRecord.SenderAccountId
            $FraudLensRecord.ReceiverAccountId
            $FraudLensRecord.Channel
        ) | ForEach-Object {
            [System.Net.WebUtility]::HtmlEncode([string]$_)
        }

        $FraudLensRows += '<tr><td class="mono">{0}</td><td>{1}</td><td class="amount">{2}</td><td>{3}</td><td class="mono">{4}</td><td class="mono">{5}</td><td>{6}</td></tr>' -f $FraudLensCells
    }

    if ($FraudLensRows.Count -eq 0) {
        $FraudLensRows = @('<tr><td colspan="7">No transaction IDs were provided for this finding.</td></tr>')
    }

    $FraudLensEvidenceSection += @"
<details class="evidence-details">
  <summary>$FraudLensSafeRule — $FraudLensSafeName | $FraudLensMatched transaction(s) matched</summary>
  <div class="evidence-scroll">
    <p class="meta">Finding reference: $FraudLensSafeId</p>
    <table class="evidence-table">
      <thead><tr><th>Transaction ID</th><th>Timestamp (UTC)</th><th>Amount</th><th>Currency</th><th>Sender</th><th>Receiver</th><th>Channel</th></tr></thead>
      <tbody>$($FraudLensRows -join "`r`n")</tbody>
    </table>
  </div>
</details>
"@
}

$FraudLensEvidenceSection += '</section>'

$FraudLensEvidenceCss = '.evidence-section{margin-top:30px}.evidence-details{margin:14px 0;background:#fff;border:1px solid #dce5ed;border-radius:7px;overflow:hidden}.evidence-details summary{cursor:pointer;padding:13px 15px;background:#eaf2f5;color:#1e555b;font-weight:600;font-size:13px}.evidence-details summary:hover{background:#dfecef}.evidence-scroll{overflow-x:auto;padding:0 12px 12px}.evidence-table{width:100%;min-width:850px;table-layout:auto;border-collapse:collapse;font-size:12px;margin-top:12px;background:#fff}.evidence-table th,.evidence-table td{padding:9px 10px;border:1px solid #dce4ed;text-align:left;vertical-align:top;overflow-wrap:anywhere}.evidence-table th{background:#203c56;color:#fff}.evidence-table tbody tr:nth-child(even){background:#f2f6fa}.evidence-table td{color:#34465a}.evidence-table .mono{font-family:Consolas,monospace;font-size:11px}.evidence-table .amount{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}'

$Html = $Html.Replace('</style>', ($FraudLensEvidenceCss + '</style>'))
$Html = $Html.Replace('</body>', ($FraudLensEvidenceSection + '</body>'))

$FraudLensGuidanceCss = '.analyst-guidance{margin:18px 0;padding:16px 18px;background:#f0f7f7;border:1px solid #cfe4e3;border-left:4px solid #278b86;border-radius:6px}.analyst-guidance h4{margin:0 0 8px;color:#1d5b5a}.guidance-heading{font-weight:600;color:#263f55}.analyst-guidance ul{padding-left:22px;margin:8px 0}.analyst-guidance li{margin:5px 0}.guidance-limit{font-size:12px;color:#52657a;margin:10px 0 0}'
$Html = $Html.Replace('</style>', ($FraudLensGuidanceCss + '</style>'))
Set-Content -LiteralPath $HtmlPath -Value $Html -Encoding UTF8

Write-Host ''
Write-Host 'FraudLens AML report generated successfully.' -ForegroundColor Green
Write-Host ("Transactions: {0}" -f $Transactions.Count)
Write-Host ("Findings:     {0}" -f $Findings.Count)
Write-Host ("JSON:         {0}" -f $JsonPath)
Write-Host ("HTML:         {0}" -f $HtmlPath)
