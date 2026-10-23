#!/usr/bin/env python3
import re
import sys
from pathlib import Path

prd_path = Path("docs/PRD.md")
ac_path = Path("docs/ACCEPTANCE_CRITERIA.md")

if not prd_path.exists():
    print(f"FAIL: {prd_path} does not exist")
    sys.exit(1)

if not ac_path.exists():
    print(f"FAIL: {ac_path} does not exist")
    sys.exit(1)

prd_text = prd_path.read_text(encoding="utf-8")
ac_text = ac_path.read_text(encoding="utf-8")

# 1. Check requirement IDs
req_patterns = [r"\b(FR-\d{3})\b", r"\b(NFR-\d{3})\b", r"\b(UX-\d{3})\b", r"\b(PRIV-\d{3})\b", r"\b(ML-\d{3})\b", r"\b(PERF-\d{3})\b", r"\b(A11Y-\d{3})\b"]

prd_req_ids = set()
for pat in req_patterns:
    matches = re.findall(pat, prd_text)
    for m in matches:
        prd_req_ids.add(m)

print(f"Total Unique Requirement IDs in PRD: {len(prd_req_ids)}")
sorted_reqs = sorted(list(prd_req_ids))
print(f"Requirement IDs: {', '.join(sorted_reqs)}")

# Check acceptance test IDs
ac_test_ids = set(re.findall(r"\b(TC-[A-Z0-9]+-\d{3})\b", ac_text))
print(f"Total Unique Acceptance Test IDs in ACCEPTANCE_CRITERIA.md: {len(ac_test_ids)}")

# Verify 1:1 mapping
unmapped_reqs = []
for req_id in prd_req_ids:
    expected_tc = f"TC-{req_id}"
    if expected_tc not in ac_test_ids:
        unmapped_reqs.append((req_id, expected_tc))

if unmapped_reqs:
    print(f"FAIL: Unmapped requirements: {unmapped_reqs}")
    sys.exit(1)
else:
    print("SUCCESS: 100% of Requirement IDs have a matching Acceptance Test (TC-<ID>)!")

# 2. Extract presets strictly from Section 5: Planned Preset Catalogue
sec5_match = re.search(r"## 5\. Planned Preset Catalogue.*?(?=## 6\.)", prd_text, flags=re.DOTALL)
if not sec5_match:
    print("FAIL: Could not locate Section 5 in PRD")
    sys.exit(1)

sec5_text = sec5_match.group(0)
presets = re.findall(r"^\d+\.\s+\*\*(.*?)\*\*", sec5_text, flags=re.MULTILINE)
print(f"Total presets found in Section 5: {len(presets)}")
unique_presets = set(presets)
print(f"Unique presets: {len(unique_presets)}")

if len(presets) != 48:
    print(f"FAIL: Expected 48 presets, got {len(presets)}")
    sys.exit(1)

if len(unique_presets) != 48:
    print(f"FAIL: Duplicate presets found: {len(presets) - len(unique_presets)} duplicates")
    sys.exit(1)

print("SUCCESS: Exactly 48 canonical preset names appear in PRD Section 5!")
print("Presets list:")
for i, p in enumerate(presets, 1):
    print(f"  {i}. {p}")

print("\n--- ALL VALIDATIONS PASSED ---")
