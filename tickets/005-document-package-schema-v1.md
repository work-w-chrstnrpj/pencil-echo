# 005 — Document package schema v1 and atomic save

Milestone: PE-000 · Status: Resolved (2026-11-03) · Owner: Claude (spec + implementation, taken over from Codex to parallelize) · Depends on: 002

## What

Define and implement the on-disk document format: a versioned package with metadata, pages, ink, objects and assets, plus atomic save and recovery.

## Why

Gate 3 in `docs/decisions.md`. Ink and AI answers must survive save/reopen without data loss, and later migrations need a version field from day one.

## Spec (Claude writes `docs/database/document-schema-v1.md` first)

Package `<id>.pencilecho/`:

- `manifest.json`: `schemaVersion`, `id` (UUID), `type` (`canvas` | `notebook`), `title`, `revision` (Int, increments on content change only), `createdAt`, `updatedAt`.
- `pages.json`: ordered pages (`id`, size in points (A4 = 595×842), `background`: blank/lined/dotted/grid). A canvas has one unbounded page.
- `ink/<pageId>.drawing`: `PKDrawing.dataRepresentation()`.
- `objects.json`: `id`, `pageId`, `type` (`text`, `markdown`, `latex`, `image`), `frame` in page coordinates, `zIndex`, `source` (editable content), `assetRefs`, `createdBy` (`user` | `ai:<requestId>`).
- `assets/<sha256>.<ext>`: content-addressed binary assets.

Reference upstream `inspiration/src/client/app/canvas-documents.js`, `persistence.js` and `src/server/canvas-agent/document-schema.mjs` for structure ideas (provenance per ticket 003).

## Implementation scope

- `Codable` types in `DocumentModel`.
- `DocumentStore` in `Services`: create, load, save, list.
- Atomic save: write to a temp package, then `FileManager.replaceItemAt`. On load, ignore or clean orphan temp packages and keep the last good copy.
- Migration hook: `migrate(from:to:)` with a v1 no-op and a test fixture.

## Exclusions

No library UI, search index, history, trash or backup (later PE-004). No multiwindow conflict resolution beyond a revision check helper.

## Spec notes (2026-11-03)

The spec is `docs/database/document-schema-v1.md`. The `DocumentModel` types, `DocumentStore`, fixtures and tests are still open for Codex. The spec adds or settles these points beyond the ticket text:

- **`revision`** increases in memory on every committed content change, including undo and redo, never on title or view changes. Tickets 006 and 010 rely on this.
- **Atomic save** stages in `.itemReplacementDirectory`, clones unchanged ink and assets with APFS, writes `manifest.json` last, then swaps with `replaceItemAt`. A crash leaves no state that recovery has to read, so "keep the last good copy" means the live package is never touched until the swap.
- **`save(expectedRevision:)`** is the revision-check helper. A mismatch with the on-disk revision is a `conflict`, and nothing is written.
- **Load is read-only.** Fatal errors are separate from non-fatal `LoadIssue`s such as missing assets or unreadable ink, so one bad page doesn't make the whole document unopenable.
- **`conversation.json`** (for 010) and **`thumbnail.png`** (for 009) are defined now as optional v1 files. `appliedRequests` backs duplicate detection for 006.
- **Page backgrounds** are objects, `{style, spacing}`. Limits are provisional until the 004 measurements.

## Acceptance

- [x] Unit tests: round-trip of a document with 2 pages, ink, 3 object types and an asset.
- [x] Simulated interrupted save (throw mid-write) leaves the previous version loadable.
- [x] Unknown higher `schemaVersion` fails with a clear error, no data modified.
- [x] Fixtures in `tests/fixtures/documents/`.

## Implementation evidence — 2026-11-03 (Claude)

- `shared/Document/DocumentModel.swift`: `Codable` types for every v1 file, `Document` (the in-memory aggregate), limits, `AssetName` (SHA-256 naming) and the ISO 8601 coding with fractional seconds.
- `shared/Document/DocumentMigrator.swift`: the migration hook. `standard` has no steps, so 1 → 1 is a no-op. A step must set `schemaVersion` itself, or migration fails.
- `service/Persistence/DocumentStore.swift`: an actor with `create`, `load`, `save(expectedRevision:)`, `list` and `delete`.
  - Saves stage in `.itemReplacementDirectory`, write `manifest.json` last, swap with `replaceItemAt`, and clone unchanged assets.
  - Loading is read-only and returns `LoadIssue`s for the non-fatal cases.
  - File writes go through an injectable `PackageFileWriter`, so tests can interrupt a save.
- Fixtures in `tests/fixtures/documents/`: the 5 packages from the spec, each in `<name>/<id>.pencilecho/` so the package name still matches `manifest.id`. They come from `generate-fixtures.swift`, with real `PKDrawing` ink generated on macOS. PencilKit traps without a bundle identifier, so the script header gives the compile-with-Info.plist steps.
- `tests/PencilEchoTests/DocumentStoreTests.swift`: 20 Swift Testing cases.
  - They cover the spec's test list: round trip in place and to a new location, interrupted save, conflict, unsupported version, orphan asset, unknown file and key, migration hook with pre-migration copy.
  - They also cover damaged and future packages in `list`, a missing asset, unreadable ink kept byte-for-byte, structural damage, an out-of-bounds object, invalid title and asset, and create/list/delete.
- The documented `test` command on `iPad (A16)` / iOS 27.0: `TEST SUCCEEDED`, 80 tests in 7 suites, including 20/20 in `DocumentStoreTests`. A clean build gives no compiler warnings in the new files.
- Deviations from the spec:
  - All ink is rewritten from memory on each save instead of cloning unchanged ink. Ink is fully loaded anyway; the spec now says so.
  - `load` returns `LoadedDocument` instead of a tuple.
  - Unreadable ink bytes are kept in memory and re-saved unchanged, so the original is never lost. The read-only page UI is ticket 008's.
- Not covered: a real device, and very large documents. The limits stay provisional until ticket 004's A16 measurements.

