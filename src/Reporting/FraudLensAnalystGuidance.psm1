function Get-FraudLensAnalystGuidance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RuleId
    )

    switch ($RuleId) {
        'FL-001' {
            [pscustomobject]@{
                RuleId = 'FL-001'
                Heading = 'Review near-threshold transaction pattern'
                ReviewSteps = @(
                    'Confirm transaction timestamps and amounts against source records.'
                    'Review timing, frequency, recipients, and stated business purpose.'
                    'Assess whether the pattern has a documented legitimate explanation.'
                    'Document evidence reviewed, outstanding questions, and rationale.'
                )
                Limitation = 'Amounts near a threshold do not establish intent to evade reporting requirements.'
                HumanReviewRequired = $true
                AutomatedSarFiling = $false
                AutomatedAccountDecision = $false
            }
        }
        'FL-002' {
            [pscustomobject]@{
                RuleId = 'FL-002'
                Heading = 'Review shared receiving account'
                ReviewSteps = @(
                    'Confirm the distinct senders and receiving account in source records.'
                    'Review timing, amounts, channels, and known legitimate relationships.'
                    'Assess whether the shared recipient has an ordinary business purpose.'
                    'Document evidence reviewed, outstanding questions, and rationale.'
                )
                Limitation = 'A shared counterparty can occur during legitimate activity and is not, by itself, evidence of money laundering.'
                HumanReviewRequired = $true
                AutomatedSarFiling = $false
                AutomatedAccountDecision = $false
            }
        }
        default {
            [pscustomobject]@{
                RuleId = $RuleId
                Heading = 'General analyst review'
                ReviewSteps = @(
                    'Verify source transactions and fields used by the detection rule.'
                    'Gather relevant context before reaching a conclusion.'
                    'Document evidence reviewed, outstanding questions, and rationale.'
                )
                Limitation = 'Automated rule output is an investigative lead, not a determination of wrongdoing.'
                HumanReviewRequired = $true
                AutomatedSarFiling = $false
                AutomatedAccountDecision = $false
            }
        }
    }
}

Export-ModuleMember -Function Get-FraudLensAnalystGuidance
