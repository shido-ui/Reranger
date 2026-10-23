#!/usr/bin/env python3
"""
validate_architecture.py
Verification script for Prompt 06 deliverables:
1. docs/ARCHITECTURE.md (interfaces, data types, clean layering, swappability)
2. docs/decisions/ADR-0001-architecture.md (Clean Architecture ADR, invariants matrix)
3. docs/DEPENDENCIES.md (package audit, licensing, reversal triggers)
"""

import os
import sys

REQUIRED_INTERFACES = [
    "ImageImporter",
    "AnalysisEngine",
    "SceneMapRepository",
    "RenderEngine",
    "PresetCatalog",
    "ProjectRepository",
    "ExportService",
    "ModelCatalog",
    "HumanizeEngine",
]

REQUIRED_DATA_TYPES = [
    "NormalizedPoint",
    "NormalizedRect",
    "ColorVector",
    "RenderRecipe",
    "AppFailure",
    "CancellationToken",
    "ProgressUpdate",
]

REQUIRED_INVARIANTS = [
    "Invariant 1: Clean Architecture",
    "Invariant 2: Progressive Disclosure",
    "Invariant 3: Source Image Immutability",
    "Invariant 4: Offline-First Runtime",
    "Invariant 5: Zero Cloud / No Accounts",
    "Invariant 6: No Fake Controls / AI",
    "Invariant 7: Proof-Gated Native Pipeline",
    "Invariant 8: Proof-Gated ML Models",
    "Invariant 9: Asset Licensing Integrity",
    "Invariant 10: Memory & Thermal Limits",
    "Invariant 11: Tooling & Diagnostics",
    "Invariant 12: Stop-the-Line Governance",
]

def verify_architecture():
    arch_path = "docs/ARCHITECTURE.md"
    if not os.path.exists(arch_path):
        print(f"FAIL: {arch_path} does not exist.")
        return False
    
    with open(arch_path, "r", encoding="utf-8") as f:
        content = f.read()

    print(f"Checking {arch_path}...")
    for iface in REQUIRED_INTERFACES:
        if f"abstract interface class {iface}" not in content and f"class {iface}" not in content:
            print(f"FAIL: Interface '{iface}' missing from {arch_path}.")
            return False
        print(f"  [PASS] Found interface: {iface}")

    for dtype in REQUIRED_DATA_TYPES:
        if f"class {dtype}" not in content:
            print(f"FAIL: Data type '{dtype}' missing from {arch_path}.")
            return False
        print(f"  [PASS] Found data type: {dtype}")

    if "PROVISIONAL" not in content:
        print("FAIL: Provisional labels missing from ARCHITECTURE.md")
        return False
    print("  [PASS] Provisional technology labels verified.")
    return True

def verify_adr():
    adr_path = "docs/decisions/ADR-0001-architecture.md"
    if not os.path.exists(adr_path):
        print(f"FAIL: {adr_path} does not exist.")
        return False

    with open(adr_path, "r", encoding="utf-8") as f:
        content = f.read()

    print(f"Checking {adr_path}...")
    required_sections = [
        "## Status",
        "## Context & Problem Statement",
        "## Decision Drivers",
        "## Considered Options",
        "## Decision Outcome",
        "### Positive Consequences",
        "### Negative Consequences",
        "## Reversal Triggers",
        "## Product Constitution & Invariants Compliance Matrix",
    ]
    for sec in required_sections:
        if sec not in content:
            print(f"FAIL: Section '{sec}' missing in {adr_path}.")
            return False
        print(f"  [PASS] Found section: {sec}")

    for inv in REQUIRED_INVARIANTS:
        if inv not in content:
            print(f"FAIL: Invariant check '{inv}' missing in ADR compliance matrix.")
            return False
        print(f"  [PASS] Verified compliance entry: {inv}")
    return True

def verify_dependencies():
    dep_path = "docs/DEPENDENCIES.md"
    if not os.path.exists(dep_path):
        print(f"FAIL: {dep_path} does not exist.")
        return False

    with open(dep_path, "r", encoding="utf-8") as f:
        content = f.read()

    print(f"Checking {dep_path}...")
    required_pkgs = [
        "flutter_riverpod",
        "go_router",
        "drift",
        "drift_flutter",
        "path_provider",
        "path",
        "image",
        "flutter_litert",
        "flutter_test",
        "flutter_lints",
        "build_runner",
    ]
    for pkg in required_pkgs:
        if pkg not in content:
            print(f"FAIL: Package '{pkg}' missing in {dep_path}.")
            return False
        print(f"  [PASS] Found package specification: {pkg}")

    if "Copyleft Violations: 0" not in content:
        print("FAIL: Licensing copyleft check missing or violated.")
        return False
    print("  [PASS] Verified 0 copyleft violations.")
    return True

def main():
    print("=== Reranger Architecture Specification Verification ===")
    if not verify_architecture():
        sys.exit(1)
    if not verify_adr():
        sys.exit(1)
    if not verify_dependencies():
        sys.exit(1)
    print("=== ALL VERIFICATION CHECKS PASSED (100%) ===")

if __name__ == "__main__":
    main()
