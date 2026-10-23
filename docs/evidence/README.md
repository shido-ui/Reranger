# Evidence & Audit Trail Directory

This directory stores raw, unmodified execution evidence, diagnostic outputs, test logs, benchmark measurements, and environment snapshots for Reranger.

---

## 1. Directory Structure Convention
Evidence is partitioned strictly per prompt run to ensure full auditability:

```text
docs/evidence/
├── README.md
├── prompt-00/
│   ├── git_status.log
│   ├── git_diff_check.log
│   ├── directory_listing.log
│   ├── toolchain_probe.log
│   └── docs_recursive_inspection.log
├── prompt-01/
└── ...
```

---

## 2. Evidence Standards
1. **Raw Log Preservation**: Standard output and standard error from commands must be redirected directly to `.log` files without manual alteration or truncation.
2. **Deterministic Checksums**: When verifying file integrity, binary dependencies, or image transformations, compute and log SHA-256 hashes (`sha256sum <file>`).
3. **No Fabrication**: If a command or tool is unavailable or fails, record the exact exit code and error message. Never substitute simulated or placeholder data.
4. **Device Metadata**: When executing on-device or native benchmarks, record kernel version, device model, available memory, and CPU/GPU architecture.
