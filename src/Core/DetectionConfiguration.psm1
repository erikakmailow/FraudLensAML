Set-StrictMode -Version 2.0

function Import-FraudLensDetectionConfiguration {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $PSScriptRoot '..\..\config\detection-rules.json')
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    try {
        $Config = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not load configuration JSON: $($_.Exception.Message)"
    }

    if ($null -eq $Config.Rules -or
        $null -eq $Config.Rules.'FL-001' -or
        $null -eq $Config.Rules.'FL-002' -or
        $null -eq $Config.Safety) {
        throw 'Configuration is missing required sections.'
    }

    $R1 = $Config.Rules.'FL-001'
    $R2 = $Config.Rules.'FL-002'

    foreach ($Rule in @($R1, $R2)) {
        if ($null -eq $Rule.Enabled -or $Rule.Enabled -isnot [bool]) {
            throw 'Each rule must have a Boolean Enabled setting.'
        }
    }

    $MinAmount = [decimal]0
    $MaxAmount = [decimal]0
    $MinCount = 0
    $Hours = 0
    $MinSenders = 0

    if (-not [decimal]::TryParse([string]$R1.MinimumAmountInclusive, [ref]$MinAmount)) {
        throw 'FL-001 minimum amount must be numeric.'
    }
    if (-not [decimal]::TryParse([string]$R1.MaximumAmountExclusive, [ref]$MaxAmount)) {
        throw 'FL-001 maximum amount must be numeric.'
    }
    if ($MinAmount -le 0 -or $MaxAmount -le $MinAmount) {
        throw 'FL-001 amount boundaries are invalid.'
    }
    if (-not [int]::TryParse([string]$R1.MinimumTransactionCount, [ref]$MinCount) -or
        $MinCount -lt 2 -or $MinCount -gt 10000) {
        throw 'FL-001 MinimumTransactionCount must be 2 through 10000.'
    }
    if (-not [int]::TryParse([string]$R1.WindowHours, [ref]$Hours) -or
        $Hours -lt 1 -or $Hours -gt 8760) {
        throw 'FL-001 WindowHours must be 1 through 8760.'
    }
    if (-not [int]::TryParse([string]$R2.MinimumDistinctSenders, [ref]$MinSenders) -or
        $MinSenders -lt 2 -or $MinSenders -gt 10000) {
        throw 'FL-002 MinimumDistinctSenders must be 2 through 10000.'
    }

    if ($Config.Safety.RequireHumanReview -ne $true -or
        $Config.Safety.AutomatedSarFiling -ne $false -or
        $Config.Safety.AutomatedAccountDecision -ne $false) {
        throw 'Unsafe settings rejected: human review must remain required and automated decisions disabled.'
    }

    [pscustomobject]@{
        ConfigVersion = [string]$Config.ConfigVersion
        SyntheticDemoDefaults = [bool]$Config.SyntheticDemoDefaults
        Rules = [pscustomobject]@{
            FL001 = [pscustomobject]@{
                Enabled = [bool]$R1.Enabled
                MinimumAmountInclusive = $MinAmount
                MaximumAmountExclusive = $MaxAmount
                MinimumTransactionCount = $MinCount
                WindowHours = $Hours
            }
            FL002 = [pscustomobject]@{
                Enabled = [bool]$R2.Enabled
                MinimumDistinctSenders = $MinSenders
            }
        }
        Safety = [pscustomobject]@{
            RequireHumanReview = $true
            AutomatedSarFiling = $false
            AutomatedAccountDecision = $false
        }
    }
}

Export-ModuleMember -Function Import-FraudLensDetectionConfiguration
