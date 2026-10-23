# Architectural Decision Records (ADR)

This directory maintains the durable architectural decisions for Reranger. Every significant architectural, structural, or cryptographic/runtime design choice must be documented as an ADR before implementation.

---

## 1. When an ADR is Required
An ADR must be authored and reviewed when:
- Introducing or altering a core architectural layer or dependency pattern.
- Selecting native image processing libraries, platform channels, or NDK/C++ bridge architectures.
- Choosing local ML / neural model runtimes and execution formats (e.g., TFLite, ONNX, MediaPipe) for Humanize Studio.
- Changing persistence strategies, file formats, or project cache serialization.
- Modifying security, sandboxing, or offline runtime boundaries.

Minor refactorings, bug fixes, and routine UI widget additions do not require an ADR.

---

## 2. ADR Lifecycle
Each ADR progresses through the following statuses:
- **PROPOSED**: Under active authoring and peer review; not yet authorized for implementation.
- **ACCEPTED**: Reviewed, approved by the Principal Engineer, and authorized for execution.
- **REJECTED**: Evaluated and explicitly rejected with justification recorded.
- **DEPRECATED**: Formerly accepted, but no longer in active use.
- **SUPERSEDED**: Replaced by a newer decision (must reference `Superseded by ADR-XXXX`).

---

## 3. ADR File Naming Convention
ADRs are stored in this directory using zero-padded sequential numbers and kebab-case descriptive titles:
`ADR-XXXX-<descriptive-slug>.md`
Example:
`ADR-0001-offline-native-image-processing-pipeline.md`

---

## 4. ADR Document Template

Every ADR must follow this exact markdown structure:

```markdown
# ADR-XXXX: <Title of Decision>

## Status
<PROPOSED | ACCEPTED | REJECTED | DEPRECATED | SUPERSEDED>

## Context & Problem Statement
- What technical, product, or performance problem is being addressed?
- What are the constraints (Android-first, offline execution, memory/thermal limits)?

## Decision Drivers
- Driver 1 (e.g., Zero cloud leaks / total privacy)
- Driver 2 (e.g., Latency budget < 33ms per preview frame)
- Driver 3 (e.g., Strict source image immutability)

## Considered Options
1. Option 1: <Name and brief summary>
2. Option 2: <Name and brief summary>
3. Option 3: <Name and brief summary>

## Decision Outcome
Chosen Option: <Option X> because <concise justification>.

### Positive Consequences
- <Advantage 1>
- <Advantage 2>

### Negative Consequences / Trade-offs
- <Drawback / maintenance cost 1>
- <Mitigation strategy>

## Product Constitution & Invariants Compliance Matrix
| Invariant | Compliant (YES/NO) | Verification Method |
|---|---|---|
| Invariant 1: Clean Architecture | YES | Verified architectural layering |
| Invariant 2: Progressive Disclosure | YES | UI remains beginner-first |
| Invariant 3: Source Image Immutability | YES | Read-only input, distinct output |
| Invariant 4: Offline-First Runtime | YES | Zero network calls |
| Invariant 5: Zero Cloud / No Accounts | YES | No network SDKs |
| Invariant 6: No Fake Controls / AI | YES | Real, test-backed execution |
| Invariant 7: Proof-Gated Native Pipeline | YES | Benchmarks and tests in place |
| Invariant 8: Proof-Gated ML Models | YES | Validated model execution |
| Invariant 9: Asset Licensing Integrity | YES | Permissive license verified |
| Invariant 10: Memory & Thermal Limits | YES | Heap < budget, no leaks |
| Invariant 11: Tooling & Diagnostics | YES | Analyzer & tests clean |
| Invariant 12: Stop-the-Line Verification | YES | Evidence logs preserved |

## References & Links
- Link to relevant PRDs, issue logs, or benchmark evidence.
```

---

## 5. Architectural Decision Register

| ADR ID | Title | Status | Date Decided |
|---|---|---|---|
| [ADR-0001](file:///root/reranger/docs/decisions/ADR-0001-architecture.md) | Clean Architecture Layering, Routing, State Management, and Local Persistence | ACCEPTED (Provisional) | 2026-10-22 |
| [ADR-0002](file:///root/reranger/docs/decisions/ADR-0002-humanize-model-runtime.md) | Humanize Model & Runtime Architecture — Native GGML Latent Diffusion and On-Demand Delivery | ACCEPTED (Outcome A) | 2026-10-22 |

