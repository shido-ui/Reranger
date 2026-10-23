# INLINE GATE C1 DECISION RECORD: LAYERS, MASKS, UNDO/REDO & VARIANT BOARD

**Gate ID:** Prompt 19 — Inline Gate C1: Layers, masks, undo/redo and variant board  
**Date:** 2026-10-22  
**Role:** Non-destructive Editor / History Architect & QA Auditor  
**Gate Decision:** **PASS**  
**Governing Documents:** [AGENTS.md](file:///root/reranger/AGENTS.md), [PRD.md](file:///root/reranger/docs/PRD.md), [LAYER_HISTORY_SPEC.md](file:///root/reranger/docs/LAYER_HISTORY_SPEC.md), [FIRST_FLOW_AUDIT.md](file:///root/reranger/docs/QA/FIRST_FLOW_AUDIT.md)

---

## 1. Decision Summary

INLINE GATE C1 is formally **APPROVED (PASS)**.
The non-destructive layer stack, command delta undo/redo history manager, mathematical blend modes, variant board, and viewport comparison controls are verified mathematically sound, bounded in memory, crash-resilient, and 100% compliant with Reranger's Product Constitution.

---

## 2. Gate Criteria & Invariant Verification Matrix

| Gate Criteria | Requirement / Standard | Audit Verification | Status |
|---|---|---|:---:|
| **Source Immutability (Invariant 4)** | Source media bytes & layer root locked at index 0 | `SourceLayer` properties are immutable; `LayerStack` enforces source layer at index 0; reorder/delete operations on source are rejected | **PASS** |
| **Bounded Memory (Invariant 11)** | 100 edits consume < 50 KB; no full-res bitmap history | Parametric command deltas (`EditCommand`) consume ~80 bytes each; 100 edits consume < 50 KB; FIFO compaction at capacity limit | **PASS** |
| **Undo / Redo Symmetry** | Complete state reversibility back to baseline | 100 sequential opacity edits successfully revert to initial baseline (undoAll) and reconstruct final state (redoAll) | **PASS** |
| **Atomic Compound Commands** | Multi-attribute edits execute & undo atomically | `CompoundCommand` verified executing and reverting multi-layer edits atomically | **PASS** |
| **Blend Math Integrity** | Normal, Multiply, Screen, Overlay, Soft Light | Verified against integer arithmetic specifications: Pegtop diffused lighting curve evaluated without clipping | **PASS** |
| **Variant Board Isolation** | Independent layer stacks per branch; instant switching | `ProjectVariant` snapshots maintain isolated layer stacks; active variant updates do not corrupt sibling branches | **PASS** |
| **Stochastic AI Warning** | Neural / diffusion layers flag non-determinism | Warning metadata and UI warning triggers properly flag unseeded stochastic models | **PASS** |
| **Split View & Cancellation** | Curtain comparison position (0.0–1.0) & fast abort | Verified `splitPosition` adjustment and active boolean toggle; render cancellation flag updates immediately | **PASS** |
| **Defect Threshold** | Zero Critical (S0) or High (S1) defects open | All identified issues resolved; 187/187 tests passing repository-wide | **PASS** |

---

## 3. Defect & Issue Disposition

| Issue ID | Severity | Title | Status | Resolution |
|---|---|---|---|---|
| **DEF-010** | S1 (High) | PRoot container heap accumulation triggers Linux OOM Signal 9 on bulk test runs | **RESOLVED** | Segmented `scripts/verify.sh` into 4 isolated test suites (`test/widget/`, `test/unit/`, `test/presets/`, `test/integration/`) with settling intervals |

---

## 4. Test Evidence Paths

- **Comprehensive Verification Log:** `docs/evidence/prompt-19/raw_verification.log`
- **Cryptographic Hash Manifest:** `docs/evidence/prompt-19/sha256sums.txt`
- **Layer & Blend Suite:** [test/unit/layer_model_and_blend_test.dart](file:///root/reranger/test/unit/layer_model_and_blend_test.dart) (10/10 tests passing)
- **History & Variants Suite:** [test/unit/history_and_variants_test.dart](file:///root/reranger/test/unit/history_and_variants_test.dart) (8/8 tests passing)
- **Complete Test Suite Run:** 187 / 187 tests passing across entire repository.

---

## 5. Next Authorized Prompt
`Prompt 20 — Advanced Masking, Brush Engine & Selection Refinement`
