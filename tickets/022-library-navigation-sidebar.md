# 022 — Library navigation: sidebar, favorites, search and sort

Milestone: PE-004 · Status: Open · Owner: OpenCode · Depends on: 009

## What

Turn the library into a two-column layout like PenEcho's: a sidebar with Recent, Favorites and All Documents, and a main area with search, sort and a list/grid switch.

## Why

Owner review of PenEcho (2026-11-04) asked to take inspiration from its navigation. Pencil Echo's library (`application/App/Library/LibraryView.swift`) is one grid with New Canvas, New Notebook, Rename and Delete. PE-004 already plans search and bookmarks (`docs/development-plan/development-plan.md`).

Upstream reference (layout only): `inspiration/public/index.html` lines 281–375 (library sidebar with Recent, Favorites, Canvases and Notes; search; sort; list/grid view), `inspiration/docs/canvas-library-pagination.md`.

## Scope

- **Layout:** `NavigationSplitView` with a sidebar and the document area. In compact width the sidebar collapses as usual.
- **Sidebar sections:** Recent (opened in the last 30 days, newest first), Favorites, All Documents, and filters for Canvases and Notebooks. AI Settings moves to the bottom of the sidebar.
- **Favorites:** a star in each document's context menu. The star in the editor top bar waits for ticket 020; if 020 hasn't merged, leave it for a follow-up. Stored in document metadata, following the ticket 005 migration rules.
- **Last opened:** record when a document was last opened, for Recent.
- **Search:** `.searchable` over document titles. Searching handwriting or AI answers is out of scope.
- **Sort:** last modified, last opened, title, created. Remembered across launches.
- **List/grid switch:** the current thumbnail grid, plus a list with a small thumbnail, title, type and modified date. Remembered across launches.
- **Empty states** for each section ("No favorites yet").
- **Accessibility:** sidebar and rows work with VoiceOver and keyboard; favorite state is announced.

## Exclusions

- Folders, projects and tags (later PE-004 work).
- Notes and knowledge cards.
- Trash, history and restore (PE-004).
- Cloud or local-vs-cloud storage choice. Documents stay local.
- Searching inside documents.

## Affected areas

`application/App/Library/LibraryView.swift`, `LibraryModel.swift`, `application/App/Editor/DocumentEditorView.swift` (favorite button), `service/Persistence/DocumentStore.swift` (metadata), `shared/Document/` (favorite and last-opened fields), `docs/database/document-schema-v1.md`, `tests/PencilEchoTests/`, `tests/PencilEchoUITests/`.

## Acceptance

- [ ] Starring a document shows it under Favorites; unstarring removes it; the state survives relaunch.
- [ ] Opening a document moves it to the top of Recent.
- [ ] Search filters by title as you type.
- [ ] Sort and list/grid choices survive relaunch.
- [ ] Existing documents without the new fields open and appear under All Documents.
- [ ] The sidebar and list work with VoiceOver. *(Owner A16 check.)*

## Automated checks

- Unit tests: favorite and last-opened persistence, migration of existing packages, Recent window, sort order for each key, title search.
- UI tests (isolated Debug library, as in ticket 009): star a document and find it under Favorites, search, switch to list view.
- Screenshot evidence in `tests/evidence/022/`.

## Device and provider gates

Owner A16 check in landscape and portrait. No provider needed.

## Stop conditions

Stop and ask the owner if favorites or last-opened need to sync across devices; that changes where the data is stored.
