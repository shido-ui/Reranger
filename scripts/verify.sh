#!/usr/bin/env bash
set -euo pipefail

# Cap Dart VM heap to 512MB to strictly prevent Linux ARM64 PRoot OOM Signal 9
export DART_VM_OPTIONS="--old_gen_heap_size=512"

echo "=========================================================="
echo "RERANGER LOCAL CI & FOUNDATION VERIFICATION SCRIPT"
echo "=========================================================="
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Host OS: $(uname -s) $(uname -m)"
echo "Flutter: $(which flutter || true)"
echo "----------------------------------------------------------"

# Step 1: Formatting check
echo "[1/7] Checking Dart code formatting..."
dart format --output=none --set-exit-if-changed lib/ test/

# Step 2: Static Analysis (Direct dart analyze minimizes VM footprint and avoids OOM Signal 9)
echo "[2/7] Running static analysis..."
dart analyze lib test
sync || true
sleep 1

# Step 3: Security, Privacy & License Audit
echo "[3/7] Running security, privacy, and dependency licensing scan..."
python3 scripts/audit_security_licenses.py

# Step 4: Native C/C++ Engine Unit Tests
echo "[4/7] Running native C/C++ tests..."
NATIVE_TESTS_STATUS="NOT RUN"
if command -v ctest >/dev/null 2>&1; then
  ran_any=0
  if [[ -d "poc/classical_engine/cpp/build" ]]; then
    echo "  -> Running classical C++ engine tests (CTest)..."
    (cd poc/classical_engine/cpp/build && ctest --output-on-failure)
    ran_any=1
  fi
  if [[ -d "native/humanize-poc/build" ]]; then
    echo "  -> Running humanize C++ spike tests (CTest)..."
    (cd native/humanize-poc/build && ctest --output-on-failure)
    ran_any=1
  fi
  if [[ $ran_any -eq 1 ]]; then
    NATIVE_TESTS_STATUS="PASSED"
  else
    NATIVE_TESTS_STATUS="SKIPPED (build directories absent)"
    echo "  Notice: Native build directories absent. Native unit tests SKIPPED."
  fi
else
  NATIVE_TESTS_STATUS="SKIPPED (ctest not installed on host)"
  echo "  Notice: ctest not found on host. Native unit tests SKIPPED on headless container."
fi

# Step 5: Unit & Widget Tests (Segmented by suite to prevent PRoot heap accumulation & OOM Signal 9)
echo "[5/7] Running Flutter tests (bounded concurrency, segmented suites)..."
echo "  -> Running widget & visual QA tests (excluding ally_matrix_probe_test.dart)..."
# ally_matrix_probe_test.dart is temporarily excluded from local CI execution due to PRoot Linux container resource constraints.
# The full 32-viewport matrix is deferred to the physical Mobile MCP Cloud Device (Google Pixel 10).
# Local CI executes responsive overflow checks with a single baseline viewport (360x800 at 1.0 scale).
WIDGET_TESTS=$(find test/widget -maxdepth 1 -name "*_test.dart" ! -name "ally_matrix_probe_test.dart" | sort)
flutter test --concurrency=1 $WIDGET_TESTS
sync || true
sleep 2

echo "  -> Running core unit tests..."
CORE_UNIT_TESTS=$(find test/unit -maxdepth 1 -name "*_test.dart" ! -name "release_candidate_*" | sort)
flutter test --concurrency=1 $CORE_UNIT_TESTS
sync || true
sleep 2

echo "  -> Running release candidate red-team unit tests (Batches A-E)..."
RC_UNIT_TESTS=$(find test/unit -maxdepth 1 -name "release_candidate_*" | sort)
flutter test --concurrency=1 $RC_UNIT_TESTS
sync || true
sleep 2

echo "  -> Running preset tests..."
flutter test --concurrency=1 test/presets/
sync || true
sleep 2

echo "  -> Running integration tests..."
flutter test --concurrency=1 test/integration/
sync || true
sleep 2

echo "  -> Running benchmark tests..."
flutter test --concurrency=1 test/benchmarks/
sync || true
sleep 2

# Step 6: Syntax & Whitespace Integrity
echo "[6/7] Checking Git diff whitespace and syntax..."
git diff --check

# Settle memory between heavy isolate phases
sync || true
sleep 2

# Step 7: Application Bundle & APK Build
echo "[7/7] Compiling application bundle..."
if [[ -n "${ANDROID_HOME:-}" || -n "${ANDROID_SDK_ROOT:-}" ]]; then
  flutter build bundle
  echo "Building Android debug APK..."
  flutter build apk --debug
else
  flutter build bundle --target-platform linux-arm64
  echo "Notice: ANDROID_HOME not set on headless container. flutter build bundle (--target-platform linux-arm64) verified."
fi

echo "=========================================================="
echo "RERANGER VERIFICATION SUMMARY"
echo "  - Formatting: PASSED"
echo "  - Static Analysis: PASSED"
echo "  - Security & Licenses: PASSED"
echo "  - Native C++ Tests: ${NATIVE_TESTS_STATUS}"
echo "  - Flutter Unit & Widget Tests: PASSED"
echo "  - Whitespace & Diff Check: PASSED"
echo "=========================================================="
