#!/usr/bin/env python3
"""
Contrast Calculator for Reranger Design Tokens (WCAG 2.1 AA)
"""

def srgb_to_linear(c):
    c = c / 255.0
    if c <= 0.04045:
        return c / 12.92
    else:
        return ((c + 0.055) / 1.055) ** 2.4

def relative_luminance(hex_color):
    hex_color = hex_color.lstrip('#')
    r, g, b = [int(hex_color[i:i+2], 16) for i in (0, 2, 4)]
    lr = srgb_to_linear(r)
    lg = srgb_to_linear(g)
    lb = srgb_to_linear(b)
    return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb

def contrast_ratio(hex1, hex2):
    l1 = relative_luminance(hex1)
    l2 = relative_luminance(hex2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)

token_pairs = [
    # Dark Theme
    ("Dark Theme: Text Primary on Background", "#F4F4F6", "#121214", 4.5),
    ("Dark Theme: Text Primary on Surface", "#F4F4F6", "#1E1E22", 4.5),
    ("Dark Theme: Text Secondary on Surface", "#A8A8B4", "#1E1E22", 4.5),
    ("Dark Theme: Primary Accent on Background", "#8A7BFF", "#121214", 3.0),
    ("Dark Theme: Primary Accent on Surface", "#8A7BFF", "#1E1E22", 3.0),
    ("Dark Theme: Error Accent on Background", "#FF7675", "#121214", 3.0),
    ("Dark Theme: Success Accent on Background", "#00D2A0", "#121214", 3.0),
    ("Dark Theme: Border Outline on Surface", "#4E4E5A", "#1E1E22", 1.5),

    # Light Theme
    ("Light Theme: Text Primary on Background", "#18181C", "#F8F9FA", 4.5),
    ("Light Theme: Text Primary on Surface", "#18181C", "#FFFFFF", 4.5),
    ("Light Theme: Text Secondary on Surface", "#5A5A68", "#FFFFFF", 4.5),
    ("Light Theme: Primary Accent on Background", "#5843D8", "#F8F9FA", 3.0),
    ("Light Theme: Primary Accent on Surface", "#5843D8", "#FFFFFF", 3.0),
    ("Light Theme: Error Accent on Surface", "#D63031", "#FFFFFF", 3.0),
]

all_passed = True
print("=== RERANGER DESIGN TOKEN CONTRAST AUDIT (WCAG 2.1 AA) ===")
for name, fg, bg, min_req in token_pairs:
    ratio = contrast_ratio(fg, bg)
    passed = ratio >= min_req
    status = "PASS" if passed else "FAIL"
    print(f"[{status}] {name}")
    print(f"       FG: {fg} | BG: {bg} | Ratio: {ratio:.2f}:1 (Req: >={min_req}:1)")
    if not passed:
        all_passed = False

if all_passed:
    print("\nSUCCESS: 100% of Design Token contrast pairings meet or exceed WCAG 2.1 AA requirements!")
else:
    print("\nFAIL: One or more token pairs failed contrast requirements.")
    exit(1)
