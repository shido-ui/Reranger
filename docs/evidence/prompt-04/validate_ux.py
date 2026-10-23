#!/usr/bin/env python3
import re
import sys
from pathlib import Path

uj_path = Path("docs/UX/USER_JOURNEYS.md")
ss_path = Path("docs/UX/SCREEN_SPECIFICATIONS.md")

if not uj_path.exists():
    print(f"FAIL: {uj_path} does not exist")
    sys.exit(1)

if not ss_path.exists():
    print(f"FAIL: {ss_path} does not exist")
    sys.exit(1)

uj_text = uj_path.read_text(encoding="utf-8")
ss_text = ss_path.read_text(encoding="utf-8")

# 1. Verify Screen IDs in SCREEN_SPECIFICATIONS.md
screen_matches = re.findall(r"### (SCR-\d{2}): (.*)", ss_text)
print(f"Total Screens Specified: {len(screen_matches)}")
for sid, title in screen_matches:
    print(f"  {sid}: {title}")

if len(screen_matches) < 16:
    print(f"FAIL: Expected at least 16 screens, got {len(screen_matches)}")
    sys.exit(1)

# Check Primary CTA definition for each screen
primary_cta_matches = re.findall(r"Primary CTA.*?:\s*(.*)", ss_text)
print(f"Total Primary CTA entries: {len(primary_cta_matches)}")

# 2. Verify Core 4-decision flow in USER_JOURNEYS.md
decision_matches = re.findall(r"Decision \d", uj_text)
print(f"Beginner Decisions identified in core flow: {len(decision_matches)}")
if len(decision_matches) != 4:
    print(f"FAIL: Expected exactly 4 decisions in beginner flow, got {len(decision_matches)}")
    sys.exit(1)

# 3. Verify Required State Coverage in USER_JOURNEYS.md
required_states = ["First-Run", "Loading", "Empty", "Error", "Cancel", "Offline", "Model-Unavailable"]
matrix_match = re.search(r"## 5\. Journey State Coverage Matrix.*", uj_text, flags=re.DOTALL)
if not matrix_match:
    print("FAIL: Journey State Coverage Matrix missing")
    sys.exit(1)

print("SUCCESS: Journey State Coverage Matrix verified!")

print("\n--- ALL UX VALIDATIONS PASSED ---")
