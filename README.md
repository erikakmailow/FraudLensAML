# FraudLens AML

**Financial Crime Intelligence and Investigative Triage Toolkit**

## Version

`0.1.0` — initial portfolio release.

## Purpose

FraudLens AML is a PowerShell-based demonstration project that analyzes synthetic transaction records and surfaces potentially relevant patterns for qualified human review.

It is intended as a portfolio and learning project, not as a production AML platform or a substitute for an institution's approved investigation, compliance, or reporting procedures.

## Current capabilities

- Validates transaction input before analysis.
- Detects repeated transactions within a configurable amount band (FL-001).
- Detects receiving accounts shared by multiple distinct senders (FL-002).
- Retains transaction references to support evidence review.
- Generates timestamped JSON and HTML reports.
- Provides analyst-oriented review guidance and explicit limitations.
- Includes a regression-test script for the detection scenarios.

## Detection rules

### FL-001 — Repeated transactions within an amount band

Identifies groups of transactions that meet the configured amount and time-window criteria. Such patterns may warrant review, but amounts near a threshold do not establish an intent to evade reporting or prove misconduct.

### FL-002 — Shared receiving account

Identifies receiving accounts associated with multiple distinct senders under the rule's criteria. A shared receiving account can have legitimate explanations and is not proof of money laundering.

Findings are investigative leads. Analysts must validate the underlying records, consider legitimate explanations, and document their rationale.

## Project structure

- `config/` — configuration location; inspect local project files for available settings.
- `data/synthetic/` — fictional demonstration transactions and expected results.
- `logs/` — local diagnostic logs.
- `reports/` — generated JSON and HTML reports.
- `scripts/` — report-generation entry point.
- `src/Core/` — input validation.
- `src/Detection/` — detection rules.
- `src/Reporting/` — analyst guidance and reporting support.
- `tests/` — regression tests.

## Requirements

- Windows PowerShell 5.1.
- Git is recommended for version control.
- Run the project only in an environment where you are authorized to execute its scripts.

## Generate a demonstration report

Open Windows PowerShell 5.1 and run:

```powershell
Set-Location (Join-Path $env:USERPROFILE 'Documents\FraudLensAML')
.\scripts\New-FraudLensReport.ps1
```

The script reads the bundled synthetic transaction CSV and writes timestamped JSON and HTML reports to `reports/`.

Review the generated reports to understand the detected patterns and their supporting transaction references.

## Run regression tests

From the project root, run:

```powershell
.\tests\Detection.Tests.ps1
```

The test file is a standalone regression harness. It does not require Pester syntax or a Pester 5 installation.

A passing test run supports the tested scenarios only; it does not establish production readiness or prove that the rules detect every relevant pattern.

## Safety and limitations

- Use synthetic data for development and demonstrations.
- Do not use real customer data unless the employer has explicitly approved the data, environment, and intended use.
- The project is designed for local analysis and does not require external network access.
- Findings require qualified human review.
- The project does not automatically file Suspicious Activity Reports (SARs).
- The project does not automatically block accounts, customers, or transactions.
- Detection results may include false positives and may miss relevant activity.
- Preserve source-record references and document review decisions.
- Follow applicable law and the organization's approved compliance and data-handling procedures.

## Compatibility

Windows PowerShell 5.1.

## Development status

Early-stage portfolio demonstration. Validate the implementation, tests, report contents, and operational requirements before considering any real-world use.
