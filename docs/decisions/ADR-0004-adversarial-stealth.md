# ADR-0004: Adversarial Stealth Engine, Provenance & Detector Robustness Lab

## Status
**ACCEPTED** (Directive from Product Owner Master Addendum — Post-Prompt 23)

## Context
Reranger previously defined Non-Goal 5 in `docs/PRD.md` stating: *"No AI-Detection Evasion Claims. Reranger does not claim or market 'invisibility' against AI detectors; all transformations serve aesthetic and creative authenticity."*

In the Post-Prompt 23 Product Owner Master Addendum, the Product Owner directed the technical team to provide advanced adversarial processing, frequency-domain perturbations, and an isolated diagnostic laboratory. The stated goal is to empower digital artists with mathematical tooling to understand and alter AI-detector confidence scores while maintaining provenance transparency.

## Decision
1. **Invariant 11 Update in `AGENTS.md`**:
   Invariant 11 has been formally updated to:
   *"Reranger provides advanced adversarial processing and provenance tools. It does not guarantee authorship but explicitly provides users with mathematical perturbations designed to alter AI-detector confidence scores."*
   Strict runtime memory and thermal budgets are preserved to prevent Android OOM conditions.

2. **Dual-Feature Architecture**:
   - **Adversarial Stealth Engine (`AdversarialStealthNode`)**:
     - Fast Gradient Sign Method (FGSM) / frequency-domain perturbation implemented in high-performance C++ and evaluated via Dart `RenderGraph`.
     - Controls: $\epsilon$ (magnitude) controlled via `strength` parameter $\in [0.0, 1.0]$.
     - High PSNR / SSIM guarantee: Perturbations remain beneath human perceptual thresholds (PSNR $> 35\text{ dB}$) while altering SHA-256 pixel hashes.
     - Isolation: Cannot be injected into standard export recipes unless explicitly toggled in the dedicated Stealth Studio.
   - **Detector Robustness Lab (`lib/features/detector_lab/`)**:
     - An isolated diagnostic module completely separated from the primary render pipeline.
     - Reproducible evaluation runner supporting mock detector adapters.
     - Strict statistical metric calculation: False Positive Rate (FPR), False Negative Rate (FNR), and Area Under the ROC Curve (AUROC).
     - Read-only C2PA metadata parser supporting `Valid`, `Invalid`, and `Missing` (`"No supported provenance signal found."`) states.

3. **User-Facing Transparency (Invariant 7)**:
   - UI provides prominent warning: *"This applies adversarial noise optimized to disrupt AI detection algorithms. It does not guarantee human authorship."*
   - Real-time preview allows inspecting noise difference before export.

## Consequences
- **Positive:** Artists gain local, transparent, on-device diagnostic tools for adversarial robustness and provenance analysis without cloud dependency.
- **Guardrails:** Explicit warnings prevent misleading claims regarding human authorship. All diagnostics operate on local fixtures with deterministic metrics.
