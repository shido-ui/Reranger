# RERANGER — PROJECT FORMAT SPECIFICATION & PERSISTENCE ARCHITECTURE

- **Format Version:** `1.0.0`
- **Specification Status:** APPROVED & IMPLEMENTED
- **Target Platform:** Android-First (Offline Local Runtime)
- **Primary Invariants:** Invariant 4 (Source Image Immutability), Invariant 5 (100% Offline-First Runtime), Invariant 6 (Zero Cloud/Accounts)

---

## 1. Architectural Philosophy & Storage Model

Reranger adheres strictly to non-destructive image manipulation:
1. **Source Image Immutability:** User source images are strictly opened read-only. Source files are never modified, overwritten, or re-compressed in-place.
2. **Hybrid Storage Architecture:**
   - **Structured Metadata & Recipes:** Stored in a local, migration-capable SQLite relational database (`projects.db`).
   - **Large Binary Payloads (Media, Masks, Outputs):** Stored as distinct files within the app-private sandbox filesystem. Raw pixel buffers or large binary blobs are never stored directly in SQLite table rows.
3. **Dirty Crash Journaling:** Uncommitted parametric edits are written to an atomic dirty journal table (`dirty_journal`), allowing immediate crash recovery if the operating system terminates the process during active editing.
4. **Scene Map Caching:** Color palettes, luminance histograms, and spatial metadata are indexed by source hash and recipe parameters (`scene_map_cache`), allowing instant project reopening without redundant re-analysis.

---

## 2. App-Private Directory Hierarchy

Within the Android private application storage (`/data/user/0/com.reranger/app_flutter/` or `context.filesDir`):

```text
app_flutter/
├── database/
│   ├── projects.db           # SQLite database file (WAL mode enabled)
│   ├── projects.db-wal       # Write-Ahead Log journal
│   └── projects.db-shm       # Shared memory index
└── projects/
    └── <projectId>/          # Project sandbox root (UUID v4)
        ├── source/           # Internal read-only working copy / verification link
        ├── masks/            # Touch-drawn or neural segmentation binary masks (.png / .bin)
        ├── outputs/          # High-resolution rendered export artifacts (.png / .jpg / .webp)
        └── cache/            # Serialized scene maps, downscaled proxies, and UI thumbnails
```

---

## 3. Relational Database Schema (`projects.db`)

The database is managed with SQLite `PRAGMA user_version` migrations.

### 3.1 Table: `projects`
Captures project identity, source metadata, recipe graph, and export state.

| Column Name | Data Type | Constraints | Description |
|---|---|---|---|
| `id` | `TEXT` | `PRIMARY KEY` | Unique project UUID v4. |
| `name` | `TEXT` | `UNIQUE NOT NULL` | User-visible project title. Unique to prevent ambiguous names. |
| `source_path` | `TEXT` | `NOT NULL` | Absolute filesystem path to immutable source media. |
| `source_hash` | `TEXT` | `NOT NULL` | SHA-256 cryptographic digest of the source media file. |
| `source_width` | `INTEGER` | `NOT NULL` | Original pixel width. |
| `source_height`| `INTEGER` | `NOT NULL` | Original pixel height. |
| `created_at` | `TEXT` | `NOT NULL` | ISO 8601 UTC creation timestamp. |
| `updated_at` | `TEXT` | `NOT NULL` | ISO 8601 UTC last modification timestamp. |
| `active_studio`| `TEXT` | `NOT NULL` | Current creative mode (`recolor`, `style`, `humanize`). |
| `active_preset_id`| `TEXT` | `NOT NULL` | Identifier of active preset (e.g. `warm_glow`, `anime_delicate`). |
| `master_intensity`| `REAL` | `NOT NULL` | Master transformation intensity $s \in [0.0, 1.0]$. |
| `recipe_json` | `TEXT` | `NOT NULL` | Serialized JSON representation of the complete `RenderRecipe`. |
| `scene_map_key`| `TEXT` | `NULL` | Cache key referencing `scene_map_cache` for instant editor open. |
| `output_path` | `TEXT` | `NULL` | Path to latest rendered output file in sandbox. |
| `output_hash` | `TEXT` | `NULL` | SHA-256 checksum of the rendered output file. |
| `is_dirty` | `INTEGER` | `DEFAULT 0` | Boolean flag (1/0) indicating unsaved in-memory state. |
| `is_corrupted` | `INTEGER` | `DEFAULT 0` | Boolean flag (1/0) indicating failed file integrity validation. |
| `is_favorite` | `INTEGER` | `DEFAULT 0` | Added in Migration V2: User favorite indicator. |
| `tags` | `TEXT` | `NULL` | Added in Migration V2: Comma-separated user tag metadata. |

### 3.2 Table: `dirty_journal`
Enforces atomic crash recovery. Contains at most one active record.

| Column Name | Data Type | Constraints | Description |
|---|---|---|---|
| `id` | `INTEGER` | `PRIMARY KEY CHECK (id = 1)` | Singleton identifier. |
| `project_id` | `TEXT` | `NOT NULL` | ID of the project being edited. |
| `recipe_json` | `TEXT` | `NOT NULL` | Complete in-progress recipe snapshot. |
| `written_at` | `TEXT` | `NOT NULL` | ISO 8601 UTC write timestamp. |

### 3.3 Table: `scene_map_cache`
Stores extracted palettes, K-means clusters, and histograms to avoid redundant re-analysis.

| Column Name | Data Type | Constraints | Description |
|---|---|---|---|
| `cache_key` | `TEXT` | `PRIMARY KEY` | SHA-256 digest of source hash + analysis parameters. |
| `source_hash`| `TEXT` | `NOT NULL` | Source media hash for quick invalidation. |
| `analysis_json`| `TEXT`| `NOT NULL` | Extracted palette vectors and histogram bin arrays. |
| `cached_at` | `TEXT` | `NOT NULL` | ISO 8601 UTC timestamp. |

---

## 4. Recipe Graph JSON Specification (`recipe_json`)

The non-destructive recipe describes the exact parameters required to reproduce the visual transformation from the source image:

```json
{
  "recipeId": "rec_01928374-1234-7890-abcd-ef0123456789",
  "recipeVersion": 1,
  "sourceImageHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "sourceImagePath": "/data/user/0/com.reranger/app_flutter/projects/proj_001/source/input.png",
  "activeStudio": "recolor",
  "activePresetId": "warm_glow",
  "masterIntensity": 0.85,
  "fineTuneParameters": {
    "temperature": 0.25,
    "tint": -0.10,
    "vibrance": 0.40,
    "contrast": 1.15
  },
  "curveLut256": [0, 1, 2, 3, "...", 255],
  "paletteRemap": [
    { "r": 0.95, "g": 0.45, "b": 0.20, "a": 1.0 },
    { "r": 0.20, "g": 0.30, "b": 0.85, "a": 1.0 }
  ],
  "maskPath": "/data/user/0/com.reranger/app_flutter/projects/proj_001/masks/mask_touch_01.png",
  "updatedAt": "2026-10-22T19:25:00.000Z"
}
```

---

## 5. Atomic Save & Crash Recovery Protocols

### 5.1 Atomic File Write Protocol (`AtomicFileWriter`)
To prevent corrupt files from interrupted writes or sudden power loss:
1. **Source Immutability Guard:** Assert that `destinationPath != sourceImagePath`. If an attempt is made to write to the source media path, abort immediately with `StorageFailure`.
2. **Headroom Verification:** Check available disk space. If free space is less than `payloadSize + 10MB`, abort with `LowStorageFailure`.
3. **Temporary Sibling Write:** Write payload bytes to a temporary sibling file (`${destinationPath}.tmp.$pid.$timestamp`).
4. **Hardware Flush:** Flush OS file buffers synchronously (`sink.flush()`).
5. **Checksum Computation:** Compute SHA-256 digest of written bytes.
6. **Atomic Rename:** Atomically rename the temporary file to `destinationPath` (a single POSIX filesystem directory entry swap).
7. **Failure Rollback:** In any failure scenario, remove the temporary file. The target destination remains untouched.

### 5.2 Crash Recovery Lifecycle
1. **During Live Editing:** Whenever the user adjusts sliders, a debounced snapshot is committed to SQLite `dirty_journal`.
2. **On Clean Save:** The full project record is committed to `projects` and `dirty_journal` is purged (`DELETE FROM dirty_journal`).
3. **On Application Launch:**
   - The app inspects `dirty_journal`.
   - If an entry exists, the app notifies the user with an honest prompt: "An unsaved session was recovered from an unexpected shutdown. Reopen project with recovered edits?"
   - If the user accepts, the recovered recipe is loaded into memory.
   - If dismissed, the journal is cleared.

### 5.3 Missing-File & Corruption Recovery Behavior
- **Output File Missing:** If the user or an external cleaner deleted an exported output file from disk, the project opens normally without crashing. The output reference is cleared (`outputReferencePath = null`), and the recipe remains 100% intact so the user can re-render at any time.
- **Source Image Missing or Hash Mismatched:** If the source image was deleted or altered externally, the project is flagged `isCorrupted = true`. The UI honestly informs the user that source media is unavailable, preventing further corrupt writes.

### 5.4 Orphan Cleanup Protocol
When `runOrphanCleanup()` executes:
1. Queries all active project IDs from `projects`.
2. Scans `<sandboxDir>/projects/`.
3. Deletes any directory whose name does not match an active project ID.
4. Scans all active project directories and purges any abandoned temporary files matching `*.tmp.*`.
5. Never touches external user storage directories.

---

## 6. Portable Project Package Specification (`.rrproj` / `.reranger`)

To support offline device-to-device project portability and project archiving, Reranger defines a standalone, self-contained, checksum-verified project package format.

### 6.1 Package File Layout (ZIP Container)

An `.rrproj` archive is a standard PKZip package with uncompressed or Deflate-compressed entries:

```text
<package_name>.rrproj (or .reranger)
├── manifest.json         # Cryptographic manifest of all package entries
├── project.json          # Project metadata (dimensions, timestamps, name)
├── recipe.json           # Serialized RenderRecipe DAG parameters
├── source/
│   └── <source_image>    # Exact copy of the immutable input media (.png/.jpg)
└── masks/
    └── <mask_uuid>.png   # Stored touch repair or segmentation masks (optional)
```

### 6.2 Manifest Schema (`manifest.json`)
The manifest binds all project assets into an tamper-evident cryptographic chain:

```json
{
  "format": "reranger_project_package",
  "version": 1,
  "createdAt": "2026-10-23T11:00:00.000Z",
  "originalProjectId": "proj_01928374-abcd-ef01",
  "projectName": "Emerald Forest",
  "sourceImageHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "files": {
    "source/input.png": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "recipe.json": "8a35f9921bc64d4b1a43ef81...",
    "project.json": "12984efc78ab910243fe...",
    "masks/mask_01.png": "98124efb01928374..."
  }
}
```

### 6.3 Security & Integrity Invariants

1. **Zip-Slip & Path Traversal Prevention:** The importer verifies every archive entry path before extraction. Any archive entry containing `..`, absolute paths (leading `/` or `\`), drive letters (e.g. `C:`), or suspicious characters is immediately rejected with an explicit `SecurityFailure`.
2. **Cryptographic Checksum Verification:** Every extracted file must match the SHA-256 digest specified in `manifest.json`. Mismatched, altered, or truncated files trigger an immediate rollback and `ChecksumMismatchFailure`.
3. **Storage Headroom Check:** Prior to uncompressing, the importer checks available disk space. If free space is below `uncompressedBytes + 10MB`, it halts with `LowStorageFailure`.
4. **Collision Resolution:** If a project with the same name already exists in the database, the importer appends ` (Imported)` or an incrementing counter (` (Imported 1)`), preventing unique constraint crashes and guaranteeing non-destructive coexistence.
5. **Offline Operation:** The entire export and import pipeline operates 100% locally on-device without remote servers or cloud accounts.

