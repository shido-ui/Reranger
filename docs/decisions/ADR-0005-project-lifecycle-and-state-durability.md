# ADR-0005: Project Lifecycle, Recipe Consistency, and Project-Scoped Crash Recovery

## Status
ACCEPTED

## Context & Problem Statement
In Reranger, project lifecycle, state durability, and crash recovery are critical data-integrity gates. An architectural audit revealed three primary vulnerabilities:
1. **Untruthful Initial Preset State**: New projects initialized with `activePresetId: 'default_natural'` and `activeStudio: 'recolor'`, neither of which existed in `PresetCatalog`. On project open, the editor silently defaulted to `PresetCatalog.all.first` (`graphite_pencil`), causing an undocumented mismatch between the stored recipe and rendered output.
2. **Save vs. Export Asynchrony**: The Export action rendered full-resolution images with in-memory parameter updates, but persisted only `outputReferencePath` and `outputChecksum` without updating `recipe` to describe the active parameters and layer stack. If image export succeeded but SQLite persistence failed, the app failed to report the partial failure.
3. **Global Crash Recovery Contention**: The `dirty_journal` table was constrained to a single global row (`CHECK (id = 1)`). Editing Project B immediately overwrote the uncommitted crash-recovery state of Project A, causing silent data loss on abnormal termination.

## Decision Drivers
- **Driver 1 (Truthful Initialization & Invariant 7)**: New projects must initialize with a real, registered studio and preset ID, with explicit user-visible migration paths for legacy or unrecognized IDs.
- **Driver 2 (Exact Edit State Persistence)**: Any operation that produces a saved output (Save, Export, Share, Package) must atomically commit the exact recipe, parameter values, layer stack, and variant board that generated that output.
- **Driver 3 (Project-Scoped Crash Recovery Isolation)**: Crash journals must be scoped per `project_id` so concurrent or sequential multi-project workflows never clobber uncommitted recovery states.
- **Driver 4 (Atomic Clear/Retain Rules & Partial Failure Reporting)**: Recovery state is cleared only when the recipe is durably committed to SQLite. Partial export failures (image on disk, SQLite write failure) must retain recovery state and inform the user.
- **Driver 5 (Source Immutability & Verifiable Replay)**: Original user media must remain bitwise identical before and after all edit/save/export operations.

---

## Technical Outcomes

### 1. Project Initialization & Preset Catalog Aliasing
- Changed default recipe initialization in `RenderRecipe.initial` to `activeStudio = 'style'` and `activePresetId = 'graphite_pencil'` (`PresetCatalog.defaultPresetId`).
- Registered legacy alias `'default_natural' -> BatchAPresets.graphitePencil` in `PresetCatalog._byId` alongside `'flat_illustration'` and `'vintage_film'`.
- Added user-visible, recoverable fallback in `EditorController.loadProject`: unrecognized presets migrate safely to `defaultPreset`, set `presetMigrationNotice`, and flag the project as dirty for user-confirmed persistence.

### 2. Synchronization of Save, Export & Persistence
- Added `EditorController.buildCurrentRecipe()` constructing the canonical `RenderRecipe` factoring active parameters, layers, variants, and schema v2.
- Updated `ExportSheet._executeExport` to save `currentRecipe` alongside the new `outputReferencePath` and `outputChecksum`.
- Handled partial export failure atomically: if image writing succeeds but SQLite metadata fails, the UI surfaces the partial outcome, retains `dirty_journal`, and leaves `isSaved = false`.
- Updated `ExportSheet._executeExportPackage` to package the current active recipe rather than a stale pre-edit record.

### 3. Database Migration 3: Project-Scoped Dirty Journal
- Introduced SQLite Migration 3 in `ProjectDatabase`:
  ```sql
  CREATE TABLE dirty_journal_v3 (
    project_id TEXT PRIMARY KEY,
    recipe_id TEXT NOT NULL,
    source_hash TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    recipe_json TEXT NOT NULL,
    written_at TEXT NOT NULL
  );
  ```
- `LocalProjectRepository.checkDirtyJournal([String? projectId])` validates that `journal['projectId'] == projectId`, `recipe.recipeId == journal['recipeId']`, and `recipe.sourceImageHash == journal['sourceHash']` before applying uncommitted edits. Mismatched or foreign journals are strictly rejected.
- `LocalProjectRepository.saveProject` clears only the journal for the saved `project.id`, leaving other projects' recovery states intact.

---

## Verification Evidence
Verified by 10 comprehensive regression tests in `test/unit/project_lifecycle_and_data_integrity_test.dart` and integration suite in `test/integration/first_flow_e2e_test.dart`:
- Truthful brand-new project initialization with registered defaults.
- Legacy alias and unrecognized preset migration.
- Modify parameter -> Save -> Reopen exact recipe and output reproducibility.
- Modify parameter -> Export -> Reopen exact recipe persistence.
- Two projects with simultaneous uncommitted dirty edits surviving independently.
- Strict recovery validation rejecting mismatched project and source hash journals.
- Source image bitwise immutability.
- Deleted/corrupt output recovery without recipe loss.
