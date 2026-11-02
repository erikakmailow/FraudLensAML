# FraudLens AML — Roadmap

This roadmap records the current implementation status, verified regression baseline, and release history for FraudLens AML v0.2.0.

## Completed

### 1. Core Transaction Processing

- [x] Transaction validation module
- [x] Required-field validation
- [x] Duplicate transaction ID detection
- [x] Timestamp and amount validation
- [x] Invalid transaction reporting

### 2. CSV Input Preflight

- [x] CSV structural validation before import
- [x] Quoted comma handling
- [x] Escaped quote handling
- [x] UTF-8 BOM handling
- [x] Malformed quote detection
- [x] Header validation
- [x] Field-count consistency checks
- [x] Dedicated CSV preflight regression tests

### 3. Detection Configuration

- [x] JSON-based detection configuration
- [x] Configuration validation
- [x] Rule enable/disable controls
- [x] Configurable FL-001 thresholds and time window
- [x] Configurable FL-002 distinct-sender threshold
- [x] Human-review safeguards
- [x] Automated SAR filing disabled
- [x] Automated account decisions disabled

### 4. Detection Rules

- [x] FL-001 repeated near-threshold transaction detection
- [x] FL-002 multiple-sender receiving-account detection
- [x] Validation integrated with detection
- [x] Detection regression coverage

### 5. Relationship Analysis

- [x] Directed account relationship graph
- [x] Aggregated account-to-account transaction edges
- [x] Connected-component analysis
- [x] Directed multi-hop path search
- [x] Pass-through activity candidate analysis
- [x] Relationship-analysis regression tests

### 6. Reporting

- [x] JSON report generation
- [x] HTML report generation
- [x] Detection findings and analyst guidance
- [x] Relationship graph summary
- [x] Connected-component reporting
- [x] Relationship edge evidence
- [x] Pass-through candidate reporting
- [x] Multi-hop path reporting
- [x] Reporting limitations and human-review safeguards

### 7. Regression and Compatibility

- [x] Detection test suite
- [x] Configuration test suite
- [x] Transaction validation test suite
- [x] Relationship analysis test suite
- [x] Relationship reporting test suite
- [x] CSV preflight test suite
- [x] Combined regression-test runner
- [x] PowerShell 7 regression verification
- [x] Windows PowerShell 5.1 regression verification
- [x] PowerShell 5.1 syntax audit

## Verified Regression Baseline

| Runtime | Passed | Failed |
|---|---:|---:|
| PowerShell 7.6.9 | 90 | 0 |
| Windows PowerShell 5.1 | 90 | 0 |

The combined runner currently executes six suites.

Re-run the tests after any code or test changes.

## Remaining Work

### Documentation and Release Review

- [ ] Review README accuracy against the current implementation
- [ ] Review this roadmap for completeness
- [ ] Review command examples and project structure
- [ ] Review safety language and known limitations
- [ ] Inspect generated JSON and HTML report examples
- [ ] Confirm the intended release scope and version number
- [ ] Review the complete Git diff
- [ ] Confirm no unintended files or sensitive data are included
- [ ] Obtain explicit approval before staging or committing release changes

### Future Development Candidates

These items are ideas for future work, not claims of existing functionality.

- [ ] Additional detection rules with documented rationale and tests
- [ ] More extensive synthetic datasets and edge-case scenarios
- [ ] Improved report usability and evidence navigation
- [ ] Additional performance and larger-dataset testing
- [ ] Further documentation of configuration and module interfaces

## Release and Repository Controls

- The existing `v0.1.0` tag is retained.
- The v0.2.0 development commit is `1027da43f4852857e7ea70aea1802852107c33cc` on `develop`.
- The annotated `v0.2.0` tag has been pushed to `origin`.
- Pull request #1 proposes merging `develop` into `main` and remains open for review.
- The pull request has not been merged. Merge requires explicit approval.

## Safety Principles

- Synthetic data is the default demonstration context.
- Findings are leads for qualified human review, not proof of misconduct.
- Relationship analysis does not prove that the same funds moved between accounts.
- No automated SAR filing.
- No automated account decisions.
- No production use without a separate design, security, legal, compliance, and operational review.
