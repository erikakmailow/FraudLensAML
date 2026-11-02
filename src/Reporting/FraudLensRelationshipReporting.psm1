function New-FraudLensRelationshipReportSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Graph,

        [AllowEmptyCollection()]
        [object[]]$PassThroughCandidates = @(),

        [AllowEmptyCollection()]
        [object[]]$Paths = @()
    )

    foreach ($RequiredProperty in @(
        'NodeCount',
        'EdgeCount',
        'TransactionCount',
        'ComponentCount',
        'Nodes',
        'Edges',
        'Components'
    )) {
        if ($null -eq $Graph.PSObject.Properties[$RequiredProperty]) {
            throw "Relationship graph is missing required property: $RequiredProperty"
        }
    }

    $GraphSummary = [pscustomobject]@{
        AnalysisType = 'AccountRelationshipGraph'
        NodeCount = [int]$Graph.NodeCount
        EdgeCount = [int]$Graph.EdgeCount
        TransactionCount = [int]$Graph.TransactionCount
        ComponentCount = [int]$Graph.ComponentCount
        Nodes = @($Graph.Nodes)
        Edges = @($Graph.Edges)
        Components = @($Graph.Components)
    }

    $PassThroughSummary = @(
        foreach ($Candidate in $PassThroughCandidates) {
            [pscustomobject]@{
                AnalysisType = 'PotentialPassThroughActivity'
                AccountId = [string]$Candidate.AccountId
                IncomingTransactionId = [string]$Candidate.IncomingTransactionId
                OutgoingTransactionId = [string]$Candidate.OutgoingTransactionId
                IncomingCounterparty = [string]$Candidate.IncomingCounterparty
                OutgoingCounterparty = [string]$Candidate.OutgoingCounterparty
                Currency = [string]$Candidate.Currency
                IncomingAmount = $Candidate.IncomingAmount
                OutgoingAmount = $Candidate.OutgoingAmount
                AmountDifference = $Candidate.AmountDifference
                AmountDifferencePercent = $Candidate.AmountDifferencePercent
                ElapsedMinutes = $Candidate.ElapsedMinutes
                ReviewRequired = $true
                Interpretation = 'Potential intermediary activity only. This does not establish that the same funds were transferred or that misconduct occurred.'
            }
        }
    )

    $PathSummary = @(
        foreach ($Path in $Paths) {
            [pscustomobject]@{
                SourceAccountId = [string]$Path.SourceAccountId
                TargetAccountId = [string]$Path.TargetAccountId
                HopCount = [int]$Path.HopCount
                AccountIds = @($Path.AccountIds)
                TransactionIds = @($Path.TransactionIds)
                HopEvidence = @($Path.HopEvidence)
                ReviewRequired = $true
            }
        }
    )

    [pscustomobject]@{
        AnalysisType = 'RelationshipAnalysis'
        SchemaVersion = '1.0'
        Graph = $GraphSummary
        PassThroughCandidateCount = @($PassThroughSummary).Count
        PassThroughCandidates = @($PassThroughSummary)
        PathCount = @($PathSummary).Count
        Paths = @($PathSummary)
        Safety = [pscustomobject]@{
            HumanReviewRequired = $true
            AutomatedSarFiling = $false
            AutomatedAccountDecision = $false
        }
        Limitations = @(
            'Relationship connections are investigative leads, not proof of misconduct.'
            'Transaction proximity and amount similarity do not establish that the same funds moved between accounts.'
            'Graph connections do not establish beneficial ownership, intent, or control.'
            'All relationship findings require human review.'
            'This analysis uses synthetic demonstration data and is not validated for production AML decisions.'
        )
    }
}

Export-ModuleMember -Function New-FraudLensRelationshipReportSection