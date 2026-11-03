# Local data model

Status: PROPOSED CONTRACT. Storage selected: per-document JSON + PencilKit packages; v1 format in `document-schema-v1.md` (ticket 005). Card, history, trash and backup entities are still conceptual (PE-004).

| Entity | Required conceptual data |
|---|---|
| Document | Stable ID, schema version, title, Canvas/notebook type, revision, timestamps, folder/tags, bookmark state |
| Page | Stable ID, document ID, A4 geometry, ordering, optional background settings/import asset |
| Ink | Document/page coordinate binding, PencilKit drawing data, transaction/revision association |
| Object | Stable ID, type, geometry, z-order, editable source, asset references, revision |
| Asset | Local reference, media type, size/hash, provenance when reused |
| Conversation | Document binding, user/assistant messages, explicit context references; retained locally |
| AI request | Request ID, provider/model, target revision/scope, lifecycle, retry intent; no credentials |
| Card | Independent content/assets snapshot, tags/bookmark, optional source document/page/object reference |
| History | Atomic checkpoints/transactions, revision and timestamp; bounded retention |
| Trash | Deletion date and recoverable data with defined purge policy |
| Settings | UI, selected provider/model, endpoint, opt-ins; credential reference only |

Keys reside in Keychain. Library/search indexes are derived and rebuildable; search must retain source links and tolerate recognition gaps. Recognition must not replace original ink.

Before implementation specify schema, on-disk package layout, stable IDs, atomic commit/recovery, history/trash limits, asset deduplication/collection, migration and multiwindow conflict handling. Never delete shared assets while referenced by a document, card, history or trash entry.

Backups include documents/assets/library metadata and a versioned manifest, excluding keys. Restore validates versions, paths, sizes and references before mutation; duplicate/conflicting IDs require an explicit policy. Keep existing data intact on failed validation. Automated Files backups deferred.
