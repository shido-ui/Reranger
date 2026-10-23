# ADR-0001: Clean Architecture Layering, Routing, State Management, and Local Persistence

## Status
ACCEPTED (Provisional on vertical slice PoC verification)

## Context & Problem Statement
Reranger is a production-grade, offline-first image-transformation studio built with Flutter for Android. The application must support three distinct creative studios (Recolor Studio, Style & Render Studio, and Humanize Studio) with beginner-first progressive disclosure, strict source image immutability, zero cloud dependencies, and tight memory constraints ($\le 300\text{ MB}$ preview heap).

A robust, modular architecture is required to ensure:
1. Complete separation of UI presentation from heavy native image manipulation algorithms.
2. The ability to swap underlying native C++ FFI or ML engines without altering UI widgets.
3. High-performance, non-blocking UI rendering at 60 FPS.
4. Type-safe, crash-resilient local project and variant persistence.

## Decision Drivers
- **Driver 1 (Source Image Immutability):** Architectural separation ensuring original files are opened read-only and never mutated.
- **Driver 2 (100% Offline Runtime):** Zero reliance on cloud APIs, external auth, or remote analytics.
- **Driver 3 (Beginner-First UI with 60 FPS Viewport):** Real-time slider feedback without UI thread jank.
- **Driver 4 (Engine Swappability):** Ability to test pure Dart, C++ FFI, and LiteRT neural engines behind uniform interfaces.
- **Driver 5 (Strict Memory & Thermal Headroom):** Strict budget control preventing Android Out-Of-Memory (OOM) kills.

---

## Considered Options

### 1. State Management
- **Option 1.1: `flutter_riverpod` (v3.4.x)** — Compile-safe, testable, reactive dependency injection with automatic resource disposal and no `BuildContext` dependency for domain logic.
- **Option 1.2: `flutter_bloc`** — Explicit event-driven state transitions; highly structured but introduces substantial boilerplate for rapid parametric slider interactions.
- **Option 1.3: Vanilla `ChangeNotifier` / `InheritedWidget`** — Built-in with zero external dependencies, but prone to excessive widget rebuilds and manual listener leak management.

### 2. Routing Architecture
- **Option 2.1: `go_router` (v18.1.x)** — Official Flutter declarative router supporting deep linking, state restoration, and clean route nesting for modal sheets.
- **Option 2.2: Navigator 2.0 (Imperative/Vanilla)** — Complex boilerplate for deep stack navigation and sheet transitions.

### 3. Local Project Persistence
- **Option 3.1: `drift` (v2.35.x) + `sqlite3`** — Type-safe, reactive relational persistence with compile-time query verification, automatic schema migrations, and atomic journaling.
- **Option 3.2: Raw `sqflite`** — Standard SQLite wrapper; requires manual SQL string queries and error-prone manual JSON mapping.
- **Option 3.3: Hive / Isar (NoSQL key-value)** — Fast NoSQL store, but less mature transactional integrity and historical maintenance volatility.

### 4. Image Processing & Rendering Engine
- **Option 4.1: Tiered Architecture (Flutter Fragment Shaders for Viewport + Minimal C++ FFI for Export)** — 60 FPS GPU preview via `dart:ui` `FragmentProgram`; non-destructive background export via isolated C++ kernels or `package:image`.
- **Option 4.2: Monolithic `opencv_dart`** — Full OpenCV 4 bindings; powerful but adds 15–40 MB binary bloat per ABI and bundles dozens of unused modules.

---

## Decision Outcome

1. **Layering & Structure:** Adopt **Clean Architecture** with strict layer separation:
   - `presentation/` (Flutter Widgets, Notifiers, State)
   - `domain/` (Entities, Use Cases, Abstract Engine Contracts)
   - `data/` (Drift SQLite DB, Sandbox File I/O, Shader Pipelines, Native Bridges)
2. **State Management:** Select **`flutter_riverpod` (v3.4.x)** (provisional on Prompt 07 validation) for clean dependency injection and reactive state without UI coupling.
3. **Routing:** Select **`go_router` (v18.1.x)** for declarative, type-safe navigation.
4. **Local Database:** Select **`drift` (v2.35.x)** for local project recipes, variant branching, and dirty crash-recovery journals.
5. **Rendering Pipeline:** Adopt the **Tiered Engine Architecture**:
   - Live Viewport: GLSL Fragment Shaders (`dart:ui`) running on GPU raster thread.
   - Core Analysis / File Export: Modular `RenderEngine` contract backed by background Dart isolates and minimal native C++ routines.
6. **ML Engine:** Adopt **`flutter_litert` (v3.9.x)** (provisional, gated behind Gate B) for on-device segmentation and glaze reduction.

### Positive Consequences
- Presentation layer has zero awareness of native C++ pointers, shaders, or file formats.
- Viewport achieves 60 FPS interactive slider responsiveness via GPU fragment shaders.
- Source files remain protected behind POSIX read-only flags and domain immutability assertions.
- 100% offline-first execution with zero network permissions.
- Modular engine interfaces enable seamless benchmarking and backend replacement.

### Negative Consequences / Trade-offs
- Requires maintaining abstract domain contracts and separate repository implementations.
- Code generation step (`build_runner` for Drift) required during development.

---

## Reversal Triggers & Validation Gates
- **State Management:** If `flutter_riverpod` introduces unexpected bundle bloat or analyzer friction during Prompt 07 bootstrap, reverse to standard `ChangeNotifier` / `InheritedNotifier`.
- **Database:** If `drift` code-generation creates toolchain friction in Linux ARM64 container, reverse to lightweight SQLite via raw `sqlite3` / `sqflite`.
- **Render Engine:** If fragment shaders fail on low-end Mali GPUs, provide an immediate `Isolate` CPU rendering fallback.

---

## Product Constitution & Invariants Compliance Matrix

| Invariant | Compliant (YES/NO) | Verification Method |
|---|---|---|
| **Invariant 1: Clean Architecture** | YES | Layered structure with inward dependency direction |
| **Invariant 2: Progressive Disclosure** | YES | UI controllers hide Pro curves/histograms until opt-in |
| **Invariant 3: Source Image Immutability** | YES | Domain entities enforce read-only input and SHA-256 validation |
| **Invariant 4: Offline-First Runtime** | YES | 100% local persistence via Drift SQLite; zero remote calls |
| **Invariant 5: Zero Cloud / No Accounts** | YES | Zero network permissions in manifest; no auth gates |
| **Invariant 6: No Fake Controls / AI** | YES | Every slider directly binds to shader/engine uniforms |
| **Invariant 7: Proof-Gated Native Pipeline**| YES | C++ FFI kernels gated behind benchmark proofs |
| **Invariant 8: Proof-Gated ML Models** | YES | Humanize Studio gated behind Gate B hardware check ($\ge 6\text{ GB}$) |
| **Invariant 9: Asset Licensing Integrity** | YES | 100% permissive licenses (MIT, Apache-2.0, BSD-3) |
| **Invariant 10: Memory & Thermal Limits** | YES | Peak heap bounded $< 300\text{ MB}$; background isolates manage thermal duty cycles |
| **Invariant 11: Tooling & Diagnostics** | YES | Analyzer and formatting enforced via Dart MCP |
| **Invariant 12: Stop-the-Line Governance** | YES | Reversal triggers and PoC verification gates defined |

---

## References & Links
- [`docs/ARCHITECTURE.md`](file:///root/reranger/docs/ARCHITECTURE.md): Full modular interface contracts and data types
- [`docs/DEPENDENCIES.md`](file:///root/reranger/docs/DEPENDENCIES.md): Dependency manifest and license audit
- [`docs/PRD.md`](file:///root/reranger/docs/PRD.md): Product requirements and scope lock
- [`docs/research/TECHNOLOGY_EVALUATION.md`](file:///root/reranger/docs/research/TECHNOLOGY_EVALUATION.md): Technology benchmarks and engine trade-offs
