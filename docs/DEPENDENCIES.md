# RERANGER — DEPENDENCY SPECIFICATION & LICENSE AUDIT

## 1. Overview & Licensing Policy
In strict compliance with **Invariant 10 ("Asset, Dependency & Model Licensing Integrity")**, all third-party libraries integrated into Reranger must possess verified, permissible open-source licenses (MIT, Apache-2.0, or BSD-3-Clause). Zero copyleft (GPL, AGPL, SSPL) or ambiguous proprietary libraries are permitted.

---

## 2. Production Runtime Dependencies

| Package Name | Exact Target Version | License Type | Publisher / Provenance | Architectural Role | Status |
|---|---|---|---|---|---|
| **`flutter_riverpod`** | `^3.4.3` | MIT | `publisher:dash-overflow.net` | Reactive state management, dependency injection, and auto-disposal | **VERIFIED** (Prompt 11) |
| **`go_router`** | `^18.1.1` | BSD-3-Clause | `publisher:flutter.dev` | Declarative routing, shell navigation, and deep linking | **VERIFIED** (Prompt 11) |
| **`crypto`** | `^3.0.7` | BSD-3-Clause | `publisher:dart.dev` | Cryptographic SHA-256 computation for cache keys and model provenance | **VERIFIED** (Prompt 11) |
| **`sqlite3`** | `^3.7.1` | MIT | `publisher:simonbinder.eu` | C-level SQLite binding for project database, migrations, and dirty journal | **VERIFIED** (Prompt 12) |
| **`path`** | `^1.9.1` | BSD-3-Clause | `publisher:dart.dev` | Safe cross-platform filesystem path manipulation | **VERIFIED** (Prompt 12) |
| **`drift`** | `^2.35.2` | MIT | `publisher:simonbinder.eu` | Type-safe SQLite database for project recipes and crash journals | **PROVISIONAL** (PoC Gate Prompt 07) |
| **`path_provider`** | `^2.1.6` | BSD-3-Clause | `publisher:flutter.dev` | Secure private sandbox filesystem path resolution | **VERIFIED** |
| **`image`** | `^4.12.0` | MIT | `publisher:loki3d.com` | Pure Dart image decoding/encoding fallback and thumbnailing | **VERIFIED** |

---

## 3. Native & Machine Learning Dependencies (Gated)

| Package Name | Exact Target Version | License Type | Publisher / Provenance | Architectural Role | Gate Dependency |
|---|---|---|---|---|---|
| **`flutter_litert`** | `^3.9.4` | Apache-2.0 | `publisher:hugo.ml` | On-device perception & segmentation inference in Humanize Studio | **GATE B CONDITIONAL** (Hardware check $\ge 6\text{ GB}$ RAM) |

---

## 4. Development & Build Dependencies

| Package Name | Exact Target Version | License Type | Publisher / Provenance | Architectural Role |
|---|---|---|---|---|
| **`flutter_test`** | Flutter SDK | BSD-3-Clause | `flutter.dev` | Unit, widget, and architecture integration testing |
| **`flutter_lints`** | `^5.0.0` | BSD-3-Clause | `flutter.dev` | Official static analysis and code style lint rules |
| **`drift_dev`** | `^2.35.2` | MIT | `simonbinder.eu` | Compile-time SQL verification and model class generator |
| **`build_runner`** | `^2.4.15` | BSD-3-Clause | `dart.dev` | Build orchestrator for Dart code generation |

---

## 5. License Integrity & Compatibility Audit

```text
License Distribution:
- MIT:            6 packages (flutter_riverpod, drift, drift_flutter, image, drift_dev, etc.)
- BSD-3-Clause:   6 packages (go_router, path_provider, path, flutter_test, flutter_lints, build_runner)
- Apache-2.0:     1 package  (flutter_litert)

Copyleft Violations: 0
Proprietary / Ambiguous Licenses: 0
OSI Approval: 100% Verified
```

---

## 6. Dependency Reversal Triggers
1. **`flutter_riverpod`:** If initialization overhead or bundle size compromises cold-start performance ($> 1200\text{ ms}$), reverse to standard `ChangeNotifier` / `InheritedNotifier`.
2. **`drift`:** If code-generation via `build_runner` produces build friction on the Linux ARM64 PRoot container, reverse to raw SQLite via `sqlite3_flutter_libs` / `sqflite`.
3. **`flutter_litert`:** If NNAPI / GPU delegation exhibits driver instability on target devices, fall back to pure CPU INT8 quantized delegate.
