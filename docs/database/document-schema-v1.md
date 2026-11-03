# Document package schema v1

Status: IMPLEMENTED — `shared/Document/`, `service/Persistence/DocumentStore.swift`, tests in `tests/PencilEchoTests/DocumentStoreTests.swift`. Updated: 2026-11-03 (ticket 005). Resolves gate 3 for v1 documents; history, trash, backups and archives are PE-004.

Design reference: PenEcho `inspiration/src/client/app/canvas-documents.js` and `persistence.js` @ 341e34d (AGPL-3.0-only), for the per-document limit, SHA-256-keyed assets with size caps, and a versioned bundle. Upstream stores documents in browser IndexedDB, so nothing from it is ported.

## Decisions

| Topic | v1 decision |
|---|---|
| Storage | One directory package per document, plain JSON plus PencilKit data. No database; the library is rebuilt by listing packages (ticket 009). |
| Location | `<app container>/Documents/Documents/<id>.pencilecho/`. On-device backups include it; it is not exposed to the Files app in v1. |
| Truth | The Swift `Codable` types in DocumentModel are authoritative; this document describes them. |
| Writer | One writer per document. The store serializes saves per document (one actor or serial queue), and ticket 008 opens a document in one window only. |
| Atomicity | Every save writes a complete new package beside the old one, then swaps it in with one `replaceItemAt`. A failed or interrupted save leaves the previous package untouched. |

## Package layout

```text
<id>.pencilecho/
  manifest.json          required  document identity, version, revision
  pages.json             required  ordered pages
  objects.json           required  all objects, may be an empty list
  ink/<pageId>.drawing   optional  one per page that has ink
  assets/<sha256>.<ext>  optional  content-addressed binaries
  conversation.json      optional  AI requests and messages (ticket 010)
  thumbnail.png          optional  library preview (ticket 009)
```

- File and folder names use the IDs exactly as encoded in JSON.
- A loader never trusts a file name alone: `manifest.id` must match the package name, and an asset's name must be the lowercase hex SHA-256 of its bytes plus an allowed extension.
- Files not listed here are ignored on load and are **not** carried into the next save. A future feature that needs a new file adds it to this list (a new optional file stays `schemaVersion` 1) or bumps the version (a change to an existing file).

## Common encoding

- JSON, UTF-8, `JSONEncoder` with `.sortedKeys`. Pretty-printing is optional.
- IDs: `UUID` strings as Foundation encodes them (uppercase). Compare IDs as `UUID` values, not strings.
- Dates: ISO 8601 UTC with fractional seconds, for example `2026-11-03T12:00:00.000Z`.
- Geometry: points, origin at the page's top-left, y down. `Rect` is `{ "x", "y", "width", "height" }` with finite numbers.
- Unknown JSON keys are ignored on load (logged in debug builds), so a newer build can add optional keys within v1 without breaking older builds.

## manifest.json

```json
{
  "schemaVersion": 1,
  "id": "6F1C2B0E-5D3A-4C8E-9B7A-2E1F0D9C8B7A",
  "type": "notebook",
  "title": "Calculus homework",
  "revision": 42,
  "createdAt": "2026-11-03T12:00:00.000Z",
  "updatedAt": "2026-11-03T12:30:00.000Z",
  "appVersion": "0.1 (1)"
}
```

| Field | Rule |
|---|---|
| `schemaVersion` | Integer. v1 = `1`. A higher value than the build supports → `unsupportedVersion`, nothing written. |
| `id` | Document UUID; matches the package name. Never changes. |
| `type` | `"canvas"` or `"notebook"`. Never changes. |
| `title` | 1–200 characters after trimming whitespace. Default "Untitled Canvas" or "Untitled Notebook". |
| `revision` | Integer ≥ 0; see Revision. |
| `createdAt`, `updatedAt` | `updatedAt` changes on every save that changes content or the title. |
| `appVersion` | Diagnostic only: the build that last saved. Never used for logic. |

### Revision

`revision` is the content version that AI requests and save checks compare (ticket 006, 010).

- It increases by 1 **in memory** on every committed content change: a finished stroke, an erase, an object add, edit, move, resize or delete, a page add, delete or reorder, a background change, and every undo or redo of those.
- It does not change for the title, selection, zoom, scroll or a thumbnail refresh.
- The saved value is the in-memory value at save time. It never decreases, and it is never reset by undo.

## pages.json

```json
{
  "pages": [
    { "id": "…", "size": { "width": 595, "height": 842 }, "background": { "style": "lined", "spacing": 24 } },
    { "id": "…", "size": { "width": 595, "height": 842 }, "background": { "style": "blank", "spacing": null } }
  ]
}
```

| Field | Rule |
|---|---|
| `pages` | Ordered list; array order is page order. Notebook: 1–500 pages. Canvas: exactly 1. |
| `id` | Page UUID, unique in the document. |
| `size` | Notebook pages are fixed A4: 595 × 842. A canvas page stores its current content size, which grows as the user draws near an edge (ticket 008), up to 20,000 × 20,000 (provisional until ticket 004 measurements). |
| `background.style` | `"blank"`, `"lined"`, `"dotted"` or `"grid"`. Drawn by the app, not part of the ink, never erasable. |
| `background.spacing` | Points between lines or dots, 8–96. `null` uses the style's default (24). Must be `null` for `blank`. |

## ink/&lt;pageId&gt;.drawing

- Bytes from `PKDrawing.dataRepresentation()`, in that page's coordinates. If ticket 004 keeps one canvas view across notebook pages, the editor translates strokes on load and save; the file is always page-relative.
- No file means the page has no ink. An empty drawing may be written or omitted.
- A file that `PKDrawing(data:)` cannot read is a load issue (`inkUnreadable`). The page opens empty and read-only until the user confirms, so the original bytes are not overwritten without consent.

## objects.json

```json
{
  "objects": [
    {
      "id": "…",
      "pageId": "…",
      "type": "markdown",
      "frame": { "x": 320, "y": 120, "width": 240, "height": 96 },
      "zIndex": 3,
      "source": "**Answer:** $x = 4$",
      "assetRefs": [],
      "createdBy": "ai:2C5E…",
      "createdAt": "2026-11-03T12:10:00.000Z",
      "updatedAt": "2026-11-03T12:10:00.000Z"
    }
  ]
}
```

| Field | Rule |
|---|---|
| `id` | Object UUID, unique in the document. |
| `pageId` | An existing page. |
| `type` | `"text"`, `"markdown"`, `"latex"`, `"image"` or `"plot"`. All but `image` match the canvas command object types. `plot` (ticket 016) is a function graph: its `source` is the line format in `shared/CanvasCommands/PlotSpec.swift` (`y = x^2`, optional `x: a .. b`, `y: a .. b`, `title: …`). It is rendered natively at runtime and stores no asset. Adding `plot` is an additive v1 change made before any release; older builds of this pre-release app can't open documents that contain one. |
| `frame` | Inside the page bounds; width and height ≥ 8. |
| `zIndex` | Integer; higher draws above lower within a page. Ties are broken by array order. Whether ink draws above or below objects is decided in ticket 004 and does not change this file. |
| `source` | Editable content, at most 100 KB UTF-8. For `image` it is the accessibility description and may be empty. AI-created objects are further limited to 20 KB by the command validator. |
| `assetRefs` | Asset names (`<sha256>.<ext>`) the object uses. An `image` has exactly one; the other types have none in v1. |
| `createdBy` | `"user"` or `"ai:<requestId>"`. Kept after the user edits the object. |
| `createdAt`, `updatedAt` | `updatedAt` changes on edit, move or resize. |

## assets/

- Name: lowercase hex SHA-256 of the file bytes, then `.png`, `.jpg`, `.heic` or `.pdf`. The same bytes are stored once per document.
- At most 32 MB per asset and 1 GB of assets per document (provisional).
- An asset with no `assetRefs` pointing at it is dropped at the next save. Ticket 005 has no shared or cross-document assets; PE-004 cards and trash must revisit this before deleting anything shared (`docs/database/data-model.md`).
- Load checks that the file exists and its size is in range. Hashes are checked when an asset is imported or restored, not on every load.

## conversation.json

Defined now so tickets 006 and 010 need no version bump.

```json
{
  "appliedRequests": [
    { "requestId": "…", "appliedAt": "2026-11-03T12:10:00.000Z" }
  ],
  "messages": [
    { "id": "…", "role": "user", "requestId": "…", "text": "Solve and explain", "createdAt": "…" },
    { "id": "…", "role": "assistant", "requestId": "…", "text": "Solved for x.", "createdAt": "…" }
  ]
}
```

- `appliedRequests` is the source of `appliedRequestIds` for duplicate checks (canvas commands v1). An entry is added when an answer is applied, and it stays even if the user undoes the answer.
- `role` is `"user"` or `"assistant"`; `text` is at most 16 KB. No provider names, keys, request bodies or images.
- At most 2,000 messages; when that is exceeded, the oldest messages are dropped first. `appliedRequests` entries are never dropped in v1.

## thumbnail.png

A PNG rendered from the first page's ink and objects at save time (`ThumbnailRenderer`, ticket 009), with the long edge at most 512 px. A notebook shows its whole first page; a canvas is cropped to its content. It is derived data: if it is missing or unreadable, the library shows a placeholder, and the next save regenerates it.

## Limits (provisional)

| Item | Limit |
|---|---|
| Documents per library | No hard cap in v1. Listing must stay responsive with 500. |
| Pages per notebook | 500 |
| Objects per document | 5,000 |
| `objects.json` size | 32 MB |
| Object `source` | 100 KB (AI objects 20 KB) |
| Asset | 32 MB each, 1 GB per document |
| Canvas page | 20,000 × 20,000 pt |

Exceeding a limit while editing is refused with a message. Ticket 004's A16 measurements should confirm or lower these numbers; changing a limit needs no version bump.

## Save

`DocumentStore.save(_ document: Document, expectedRevision: Int?) async throws -> SaveReceipt`

1. **Conflict check.** If `expectedRevision` is given and differs from the `revision` in the on-disk manifest, throw `conflict(onDisk:)` and write nothing. The editor passes the revision it last loaded or saved, which protects against a second writer.
2. **Stage.** Get a staging directory with `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: packageURL, create: true)`, which is on the same volume. Create `<id>.pencilecho/` inside it.
3. **Write.** Write `pages.json`, `objects.json`, the optional files, the changed ink files, and any new assets.
   - Ink is written from memory: every page's ink is loaded, so there is nothing to clone. Unreadable ink bytes are kept and written back unchanged.
   - Copy unchanged assets from the live package with `FileManager.copyItem`. On APFS this makes a clone, not a data copy.
   - Skip assets that are no longer referenced.
   - Write `manifest.json` last.
4. **Swap.** `FileManager.replaceItemAt(packageURL, withItemAt: stagedURL)`. For a new document, use `moveItem` instead.
5. **Clean up.** Remove the staging directory. Return the saved revision.

Any error before step 4 removes the staging directory and leaves the live package unchanged. A crash leaves at most a staging directory in the system's replacement area; the system cleans it up, and recovery never reads it. The worst case is losing the unsaved changes since the last save, which ticket 008 caps at the 2-second autosave window.

## Load

`DocumentStore.load(id:) async throws -> LoadedDocument` (document + `[LoadIssue]`)

Loading is read-only: it never repairs, migrates on disk, or rewrites a package.

| Problem | Result |
|---|---|
| Missing or unreadable `manifest.json`, `pages.json` or `objects.json`; `manifest.id` ≠ package name | throw `damaged(reason)` (ticket 009 shows "Can't open") |
| `schemaVersion` > supported | throw `unsupportedVersion(found:supported:)` |
| Duplicate page or object IDs, an object on a missing page, wrong page count for the type | throw `damaged(reason)` |
| Ink file unreadable | issue `inkUnreadable(pageId)`; page opens read-only |
| Asset missing or size out of range | issue `assetMissing(name)`; the object shows a placeholder |
| Frame outside page, source over limit | issue `objectOutOfBounds(id)` / `objectTooLarge(id)`; object loads as is |
| `conversation.json` or `thumbnail.png` unreadable | issue `optionalFileUnreadable(name)`; treated as absent |

The editor shows issues in a non-blocking banner.

## List

`DocumentStore.list() async -> [DocumentSummary]` reads only `manifest.json` (and `thumbnail.png` when shown) from each `*.pencilecho` directory. A package whose manifest fails to load, or whose manifest ID differs from its folder UUID, is listed with its folder name and a `damaged` state, never skipped silently. Required pages/objects corruption is checked on opening. Items sort by updatedAt descending, with filename ordering for equal dates or damaged entries. Library refresh rebuilds the list without a database.

## Create and delete

- `create(type:title:)` writes a new package through the same staging path, with revision 0, and one blank page (A4 for a notebook, 2,000 × 2,000 for a canvas).
- `delete(id:)` removes the package permanently. This is a hard delete until trash exists in PE-004 (ticket 009).

## Migration

- `DocumentMigrator.migrate(_ raw: RawPackage, from: Int, to: Int) throws -> RawPackage` works on the decoded JSON files before typed decoding. In v1 the only path is 1 → 1, which returns its input unchanged.
- A migrated document stays in memory until its first save. Before that save, the store clones the original package to `<app container>/Library/Application Support/PreMigration/<id>.pencilecho-v<old>/` and keeps it until PE-004 defines retention.
- Downgrade is not supported: an older build refuses a newer `schemaVersion` instead of opening it.

## Fixtures (`tests/fixtures/documents/`)

| Fixture | Purpose |
|---|---|
| `v1-notebook-two-pages/` | 2 lined/blank pages, ink on both, `text` + `markdown` + `latex` + `image` objects, one asset, conversation with one applied request. Round-trip test. |
| `v1-canvas-empty/` | Fresh canvas at revision 0. |
| `v99-future/` | `schemaVersion: 99`. Must fail with `unsupportedVersion`, and the files' bytes and dates stay unchanged. |
| `damaged-manifest/` | Truncated `manifest.json`. Must fail with `damaged`; list still shows it. |
| `missing-asset/` | Image object whose asset file is absent. Loads with `assetMissing`. |

Each fixture folder holds one `<id>.pencilecho` package, so the package name matches `manifest.id`. `generate-fixtures.swift` writes them deterministically, including real `PKDrawing` ink, and they are checked in so tests don't depend on drawing at runtime.

## Test cases (ticket 005 acceptance)

- Round-trip the two-page fixture: load, save to a new location, load again. Pages, ink bytes, objects, asset and conversation match.
- Interrupted save: inject a throwing file writer after `objects.json` is written. The live package is byte-identical afterwards and loads, and no staging directory remains.
- Conflict: save with a stale `expectedRevision`. Expect `conflict`, with nothing written.
- Unsupported version: as in the fixture table, with no data modified.
- Orphan asset: delete the only image object, save, and the asset file is gone.
- Unknown file in the package is not present after the next save; unknown JSON key loads without error.
- Migration hook: 1 → 1 returns its input unchanged; a test-only 0 → 1 migration in the test target proves the hook runs before decoding and that the pre-migration clone is written on first save.

## Library metadata operations (009)

`rename(id:to:)` trims/validates the 1–200-character title, preserves revision and updates updatedAt. It validates the document, clones the original package into a replacement directory, rewrites only manifest.json and atomically swaps the package. Unlike a content save, rename preserves all other file bytes, including unknown files and unreadable optional data. A pre-swap failure leaves the original intact.

`deletePackage(at:)` permits only direct package children of the store root, including damaged packages without a readable manifest UUID. The library requires explicit permanent-delete confirmation and refuses rename/delete while an editor owns that document's in-process claim. No trash/restore is provided until PE-004. See [library verification](../testing/library-009.md).

## Rich-source rendering (011)

Markdown and LaTeX continue to store their original `source` and schema-v1 `frame`. Native attributed strings and formula raster attachments are derived at runtime and are not stored as image assets. Saving an edited source or resizing its width records the measured height in the same undoable content revision; reopening uses the stored source/frame. Renderer limits and fallback never rewrite source. No schema version change or migration is needed; see [renderer limits and tests](../testing/rich-text-011.md).
