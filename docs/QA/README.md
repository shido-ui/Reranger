# Quality Assurance (QA) Strategy & Defect Governance

This document establishes the defect classification, quality gates, and verification protocol for Reranger.

---

## 1. Quality Philosophy
Reranger enforces an **Evidence-Backed, Stop-the-Line** engineering model. Quality is not inspected at the end; every vertical slice must provide reproducible, verifiable test evidence before progressing to the next stage. Simulated progress, fake test outputs, or untested features are strictly prohibited.

---

## 2. Defect Severity Classifications

| Severity | Definition | Policy / Gate Action |
|---|---|---|
| **S0 (Critical)** | System crash, fatal exception, corruption/mutation of original source images, cloud/network data leak, fake control/fake AI masquerade, or complete inability to build/test. | **IMMEDIATE STOP-THE-LINE.** Mark prompt status `FAIL` or `BLOCKED`. No gate passage permitted until root cause is identified, fixed, and verified with before/after evidence and a regression test. |
| **S1 (High)** | Core studio feature broken or non-functional (Recolor, Style & Render, Humanize), severe memory leak exceeding device budget, thermal throttling trigger, or missing mandatory test coverage. | **STOP-THE-LINE.** Mark prompt status `FAIL` or `BLOCKED`. Cannot advance to subsequent functional prompts until remediated and verified. |
| **S2 (Medium)** | Non-blocking defect, secondary UI cosmetic inconsistency, sub-optimal edge case performance, or non-critical error logging with an existing working workaround. | May proceed to subsequent prompt if explicitly cataloged in `docs/QA/ISSUE_LOG.md` with an approved mitigation plan. |
| **S3 (Low)** | Minor typo in documentation or code comments, non-functional cosmetic enhancement, minor non-user-facing code smell. | Logged in `docs/QA/ISSUE_LOG.md` and scheduled for routine cleanup. |

---

## 3. Mandatory Quality Gates
1. **Source Immutability Gate**: Automated test suite must prove that input image hashes (SHA-256) are identical before and after any image transformation pipeline runs.
2. **Network Isolation Gate**: App must run in complete network isolation; any outgoing network socket or DNS lookup during transformation pipelines fails the gate.
3. **Bounded Vertical Slice Gate**: Default limit of 8 changed source/test/config files per prompt/run.
4. **Regression Test Requirement**: Every defect fix must be accompanied by an automated regression test that reproduced the failure before the fix and passes after the fix.
5. **Static Analysis & Formatting Gate**: `dart analyze` must report 0 errors and 0 warnings, and `dart format` must be satisfied.
