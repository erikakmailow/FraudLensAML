# FraudLens AML

**Version:** 0.1.0 baseline
**Development branch:** `develop`
**Project type:** Synthetic-data AML analysis and portfolio demonstration

## Overview

FraudLens AML is a PowerShell-based project for exploring transaction validation, configurable detection rules, account-relationship analysis, and analyst-oriented reporting.

The project uses synthetic transaction data to demonstrate analytical workflows. It is not a production AML platform and must not be used as the sole basis for real-world financial, regulatory, or account decisions.

## Current Capabilities

### 1. Transaction Validation

The transaction-validation module checks transaction records for issues including:

- Missing required fields
- Blank or duplicate transaction IDs
- Missing sender or receiver account identifiers
- Transactions where the sender and receiver are the same
- Invalid timestamps
- Non-numeric or non-positive amounts
- Missing currency or channel values

Validation results identify each transaction and indicate whether it is valid, with associated error details.

### 2. CSV Preflight

The CSV preflight module checks file structure before transaction import.

It detects issues such as:

- Empty files
- Malformed quotation marks
- Unclosed quoted fields
- Unexpected characters after closing quotes
- Blank, duplicate, or missing headers
- Inconsistent field counts

Tested input support includes quoted commas, escaped quotes, and UTF-8 BOM files.

### 3. Configurable Detection Rules

Detection configuration is stored in:

`config/detection-rules.json`

The current demonstration rules are:

| Rule | Description |
|---|---|
| FL-001 | Identifies repeated transactions within a configurable near-threshold amount range and time window. |
| FL-002 | Identifies receiving accounts associated with multiple distinct senders. |

Rules can be enabled or disabled and configured through the JSON configuration file.

Detection operates on validated transaction records.

These rules produce leads for review. They do not establish that money laundering or other misconduct occurred.

### 4. Account-Relationship Analysis

The relationship-analysis module provides:

- Directed account-to-account transaction edges
- Account nodes and degree information
- Connected-component analysis
- Transaction evidence associated with graph edges
- Directed multi-hop path searches
- Candidate pass-through activity analysis

Pass-through analysis looks for qualifying incoming and outgoing transaction pairs based on elapsed time, currency, and amount similarity.

A candidate pair does not prove that the same funds moved between accounts. The analysis is intended to support further review, not establish fund tracing, intent, ownership, or misconduct.

### 5. Reporting

The reporting workflow produces JSON and HTML output containing detection findings and analyst-oriented information.

Relationship reporting can include:

- Graph summaries
- Connected components
- Transaction edge evidence
- Multi-hop path results
- Pass-through candidates
- Analyst review guidance
- Limitations and safety information

## Safety and Limitations

FraudLens AML is a synthetic-data demonstration and portfolio project.

The current safety configuration requires human review and prohibits automated suspicious activity report filing and automated account decisions.

Important limitations:

- A rule match is an analytical lead, not proof of misconduct.
- Transaction patterns and account connections require context and human review.
- Similar amounts and transaction timing do not establish that the same funds moved.
- Graph connections do not establish beneficial ownership, control, or intent.
- Synthetic demonstration results should not be treated as production findings.
- The project does not replace institutional AML policies, legal obligations, or qualified compliance review.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7
- Access to the project directory
- Synthetic CSV transaction data for demonstration and testing

No live financial account access is required for the synthetic-data test suites.

## Project Structure

```text
FraudLensAML/
├── config/
│   └── detection-rules.json
├── scripts/
│   └── New-FraudLensReport.ps1
├── src/
│   ├── Analysis/
│   │   └── FraudLensRelationships.psm1
│   ├── Core/
│   │   ├── CsvPreflight.psm1
│   │   ├── DetectionConfiguration.psm1
│   │   └── TransactionValidation.psm1
│   ├── Detection/
│   │   └── FraudLensDetection.psm1
│   └── Reporting/
│       └── FraudLensRelationshipReporting.psm1
├── tests/
│   ├── Configuration.Tests.ps1
│   ├── CsvPreflight.Tests.ps1
│   ├── Detection.Tests.ps1
│   ├── Relationships.Tests.ps1
│   ├── RelationshipReporting.Tests.ps1
│   ├── Run-All-RegressionTests.ps1
│   └── Validation.Tests.ps1
├── README.md
└── ROADMAP.md

Running the Regression Tests
From the project root, run:
.\tests\Run-All-RegressionTests.ps1


The combined runner executes six regression suites:
1. Detection
2. Configuration
3. Transaction validation
4. Relationship analysis
5. Relationship reporting
6. CSV preflight
Latest Verified Test Baseline
Runtime	Passed	Failed
PowerShell 7.6.9	84	0
Windows PowerShell 5.1	84	0

These results represent the test runs completed during development. Run the suite again after making changes.
Generating a Report
The report-generation script is:
.\scripts\New-FraudLensReport.ps1


Review the script's parameters and configuration before running it with a particular input file.

Use synthetic data for demonstration and testing.
Development Status
The 0.1.0 baseline is retained in Git.

Additional validation, configurable detection, relationship analysis, reporting, and regression coverage have been developed on the develop branch.

See ROADMAP.md for completed work and remaining release tasks.
Disclaimer
FraudLens AML is an educational and portfolio demonstration.

It is not legal, financial, or regulatory advice; it is not a substitute for a regulated institution's AML program; and it must not independently make customer, account, or reporting decisions.