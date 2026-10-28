# FraudLens AML

Financial Crime Intelligence and Investigative Triage Toolkit

## Version
0.1.0-dev

## Purpose
Analyze authorized transaction data to surface potentially relevant
patterns and relationships for qualified human review.

## Initial safety defaults
- Synthetic data for development and demonstrations.
- No external network connections.
- No automatic customer, account, or transaction blocking.
- No automated SAR filing or filing recommendations.
- Findings are investigative leads, not proof of wrongdoing.
- Detection rules must be explainable and configurable.
- Preserve source-record references for validation.
- Do not use real customer information until the employer has
  explicitly approved the data, environment, and intended use.

## Project structure
- config/          Detection configuration
- data/synthetic/  Fictional demonstration data
- logs/            Local diagnostic logs
- reports/         Generated reports
- scripts/         Entry-point scripts
- src/Core/        Input validation and shared functions
- src/Detection/   Transaction and relationship analysis
- src/Reporting/   Report generation
- tests/           Automated tests

## Compatibility
Windows PowerShell 5.1

## Development status
Scaffold only. No production detection logic is enabled yet.
