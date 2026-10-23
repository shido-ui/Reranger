# RERANGER ENVIRONMENT & TOOLCHAIN RECONNAISSANCE BASELINE

## 1. Executive Summary & Go / No-Go Recommendation
- **Reconnaissance Status:** COMPLETE & VERIFIED
- **Recommendation for Flutter App Scaffolding:** **GO** (Prerequisite Flutter SDK is installed and verified)
- **Toolchain Readiness:** The Flutter SDK (`Flutter 3.47.7 stable`, `Dart 3.13.5`) is installed at `/root/flutter/bin/flutter` and fully verified in PATH. Local ADB device count is 0. A physical remote Android device allocation flow has been initiated via the Mobile MCP server (`mobile_login_to_cloud_provider` / `mobile_allocate_remote_device`).
- **Memory & OOM Constraint Notice:** The host environment operates under strict Linux container memory headroom constraints. Heavy parallel subprocesses and unconstrained background tasks must be avoided to prevent kernel OOM kills (Signal 9), strictly aligning with Invariant 11 ("Strict Runtime Memory & Thermal Budgets").

---

## 2. Comprehensive Toolchain Matrix

| Tool / Subsystem | Exact Version / Output | Detection Status | Location / Command |
|---|---|---|---|
| **Operating System** | Linux 6.17.0-PRoot-Distro aarch64 (SMP PREEMPT_DYNAMIC) | VERIFIED | `uname -a` |
| **CPU Architecture** | ARM64 (`aarch64`) | VERIFIED | `uname -m` |
| **Available Storage** | 30 GB available (193 GB used / 223 GB total, 87% use) | VERIFIED | `df -h .` |
| **System Memory** | 11.4 GB total RAM (~1.78 GB available headroom) | VERIFIED | `/proc/meminfo` |
| **Flutter SDK** | **Flutter 3.47.7 • channel stable** (rev `abaf9c5237`) | **VERIFIED** | `/root/flutter/bin/flutter` |
| **Dart SDK** | Dart 3.13.5 (bundled with Flutter) / Dart 3.13.6 (system) | VERIFIED | `/root/flutter/bin/cache/dart-sdk` & `/usr/bin/dart` |
| **Java Development Kit** | OpenJDK 21.0.12 (build 21.0.12, mixed mode) | VERIFIED | `/data/data/com.termux/files/usr/bin/java` |
| **Gradle** | 9.8.1 (Kotlin 2.4.10, Groovy 4.0.33, Launcher JVM 21.0.12) | VERIFIED | `/data/data/com.termux/files/usr/bin/gradle` |
| **CMake** | 4.4.4 | VERIFIED | `/data/data/com.termux/files/usr/bin/cmake` |
| **Ninja** | 1.13.2 | VERIFIED | `/data/data/com.termux/files/usr/bin/ninja` |
| **Clang / LLVM** | 21.1.8 (Target: `aarch64-unknown-linux-android24`) | VERIFIED | `/data/data/com.termux/files/usr/bin/clang` |
| **Android AAPT2** | 2.20-android-16.0.0_r4 | VERIFIED | `/data/data/com.termux/files/usr/bin/aapt2` |
| **Android apksigner** | 0.9 | VERIFIED | `/data/data/com.termux/files/usr/bin/apksigner` |
| **Android Debug Bridge** | ADB 1.0.41 (Version 37.0.0p1-android-tools) | VERIFIED | `/data/data/com.termux/files/usr/bin/adb` |
| **Local Connected Devices** | 0 attached physical devices (`adb devices -l` empty) | VERIFIED (EMPTY) | `adb devices -l` |
| **Remote Cloud Device (Mobile MCP)** | Cloud fleet integration active; auth initiated | STAGED / PENDING USER AUTH | `mobile_login_to_cloud_provider` / `mobile_allocate_remote_device` |
| **Git** | 2.43.0 | VERIFIED | `/usr/bin/git` |

---

## 3. Target ABIs and Device Profiles
- **Primary Target ABI:** `arm64-v8a` (aligned with native host architecture and modern Android devices).
- **Secondary Target ABIs:** `armeabi-v7a` (32-bit legacy ARM), `x86_64` (emulator).
- **Target API Levels:**
  - `minSdkVersion`: 24 (Android 7.0 Nougat — matches host Clang target `android24`).
  - `targetSdkVersion`: 34 (Android 14) or 35 (Android 15).
  - `compileSdkVersion`: 34 / 35.
- **Hardware Device Testing Strategy:**
  - Local device count is 0.
  - To enable on-device Android validation, the Mobile MCP toolset provides access to real remote cloud devices (`mobile_allocate_remote_device`).
  - Device authentication requires one-time approval at `https://app.mobilenext.ai/login/device` (Code: `2Y6H-HPJM`).
  - Headless Dart and Linux host testing serves as the immediate verification tier.

---

## 4. Repository Baseline & Flutter Project Structure
- **Current Repository Contents:**
  - `.agents/` & `mcp_config.json`: Agent MCP server definitions.
  - `AGENTS.md`: Established product constitution with 12 non-negotiable invariants.
  - `docs/`: Governance (`STATUS.md`, `ENVIRONMENT.md`, `PRD.md`, `ACCEPTANCE_CRITERIA.md`, `decisions/`, `QA/`, `research/`, `evidence/`).
  - `lib/`: Present, clean directory (ready for vertical slice scaffolding).
  - `test/`: Present, clean directory (ready for unit and architecture tests).
- **Bootstrap Architecture Plan:**
  - `lib/src/core/` (error handling, theme, constants)
  - `lib/src/domain/` (studio entities, value objects, immutable project contracts)
  - `lib/src/data/` (local repository implementations, platform channels)
  - `lib/src/presentation/` (state notifiers, screens for Recolor, Style & Render, Humanize)

---

## 5. MCP Tools Availability Matrix

| MCP Server | Integration Status | Tools Provided | Verification Notes |
|---|---|---|---|
| **dart-flutter** | VERIFIED & ACTIVE | `analyze_files`, `pub`, `pub_dev_search`, `lsp`, `flutter_driver_command`, `widget_inspector`, `vm_service`, `hot_reload`, `hot_restart`, `get_runtime_errors`, `read_package_uris`, `rip_grep_packages`, `roots`, `dtd` | Native tools defined at `/root/.gemini/antigravity-cli/mcp/dart-flutter/` |
| **mobile** | VERIFIED & ACTIVE | `mobile_list_available_devices`, `mobile_list_remote_devices`, `mobile_allocate_remote_device`, `mobile_release_remote_device`, `mobile_login_to_cloud_provider`, `mobile_install_app`, `mobile_launch_app`, `mobile_take_screenshot` | Configured with `--insecure-storage` wrapper to support headless container authentication |
| **google-developer-knowledge** | VERIFIED & ACTIVE | `search_documents`, `get_documents`, `answer_query` | Schemas verified |
| **context7** | VERIFIED & ACTIVE | `resolve-library-id`, `query-docs` | Schemas verified |
| **github** | VERIFIED & ACTIVE | `create_or_update_file`, `get_file_contents`, `list_issues`, `create_pull_request`, etc. | Schemas verified |
| **filesystem** | VERIFIED & ACTIVE | `read_file`, `write_file`, `edit_file`, `list_directory`, etc. | Native system tool |
| **brave-search** | VERIFIED & ACTIVE | `brave_web_search`, `brave_local_search` | Schemas verified |
| **fal-ai** | VERIFIED & ACTIVE | `generate_image`, `edit_image`, `run_model`, etc. | Schemas verified |

---

## 6. Remote Cloud Device Allocation Protocol (Mobile MCP)
When local ADB devices are 0:
1. Trigger browser device authentication:
   - URL: `https://app.mobilenext.ai/login/device`
   - One-Time Code: `2Y6H-HPJM`
2. Once authorized, query available catalog via `mobile_list_remote_devices`.
3. Reserve cloud physical unit via `mobile_allocate_remote_device(platform: "android", type: "real", wait: true)`.
4. Run Flutter build and push APK to allocated cloud device for hardware validation.
5. Release device via `mobile_release_remote_device(device: <id>)` upon test completion.
