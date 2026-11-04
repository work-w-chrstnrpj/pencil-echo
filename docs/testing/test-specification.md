# Verification strategy

Status: Native simulator build/tests verified through ticket 007; physical acceptance and live-provider checks remain pending.

## Required layers

- Unit: document geometry, schema validation, request scoping, revision comparison, mutation authorization, undo transactions, provider parsing, archive validation.
- Integration: atomic save/reopen, interrupted save recovery, migration, multiwindow conflicts, index rebuilding, cards surviving deleted source, history/trash/backup restore.
- Provider contracts: each selected provider independently (Qwen first; OpenAI-compatible presets plus native Anthropic and Gemini); vision vs text-only model gating; image input, streaming/cancellation, auth/rate limits, malformed output, retries, custom endpoint and no credential cross-routing. Fixtures alone do not establish real-provider acceptance.
- MCP: independently test Codex, Claude Code and Cursor; pairing/revocation, opted-in documents, captures/edits, duplicates/stale state and background/reconnect.
- Widget: no credential access, default network denial, narrow bridge, malicious inputs, resource limits and restoration fallback.
- UI/accessibility: Canvas/notebook navigation, lasso mixed content, keyboard/trackpad, VoiceOver/Dynamic Type, rotation, multitasking and multiwindow on supported device capabilities.

## Physical acceptance

Owner's A16, USB-C Pencil, reported iPadOS 27. Record actual OS/build before execution. Test Pencil input/palm rejection and no finger drawing, mixed-layer alignment during pan/zoom, PDF annotation, long documents, memory pressure, cancellation and save/reopen. Measure performance before setting numerical capacity targets.

Primary gate: create → handwrite problem → manual solve → editable answer beside problem → undo → close/reopen with expected content. Also reopen a retained answer, edit original during pending AI and confirm review, and repeat offline to confirm preserved content/manual retry.

## Commands and evidence

Run from the workspace root. Use per-command Xcode selection; never change global `xcode-select` for this project.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

`PencilEchoTests` uses Swift Testing in a hosted unit-test target. Its three empty placeholders establish test discovery for the App, DocumentModel and Services logical groups only. `InkObjectSpikeTests.swift` adds eleven Debug-only tests for coordinate conversion/layout, transformed/masked stroke and object selection, mixed movement, combined answer undo/redo, gesture-handler movement/cancellation, ink-action ordering, bounds clamping and synthetic-load counts. Gesture states are supplied deterministically; actual touch/Pencil input remains separate. Root npm tests are copied template-tooling tests. `node bin/create-preset.mjs validate` checks context structure only.

Separate statuses: automated check, native build, simulator flow, real-provider flow and owner device acceptance. Record failures/blocked reasons without claiming success from another category.

## Scaffold verification — 2026-11-03

The exact commands above both succeeded on the iPad (A16) / iOS 27.0 simulator with Xcode 27.0 (27A266a). Swift Testing ran three placeholder tests in three suites, with zero failures. Installed and launched the built app with simctl, then visually confirmed the title and both buttons in the [portrait screenshot](../../tests/evidence/002/home-portrait.png). Built metadata confirms iPad-only, minimum OS 27.0, multiple scenes and four orientations. Rotation/multiwindow interaction and physical acceptance were not exercised.

`plutil -lint` passed for the project and Info.plist. Xcode's AppIntents metadata extraction was skipped because no AppIntents dependency exists. Context structural validation failed on an existing obsolete `wiki/` path in `inspiration/public/vendor/manim-web-licenses/splaytree-README.md`; the reference clone is excluded from this ticket and was not changed. See [ticket 002](../../tickets/002-xcode-project-scaffold.md) for full scope and evidence.

## Ink/object spike verification — 2026-11-03

The canonical simulator build and test commands passed. Final run: **14 tests in 4 suites passed**, comprising eleven spike tests and three scaffold placeholders. A Release simulator build with `-configuration Release` also passed. Programmatic portrait/landscape layout changes and zoom extrema passed; rendered seeded alignment was visually checked at 0.25×, 1× and 4×. Both layer orders and the 2,000-stroke/50-object load were rendered. See [the spike report](../spikes/004-ink-object-layer.md) and [screenshots](../../tests/evidence/004/) for measurements and limitations.

Real finger pan/pinch/lasso dispatch, native Pencil stroke undo, physical A16 footprint/frame/latency measurements and Owner + Claude review are **NOT RUN / pending**. Simulator evidence does not close those acceptance items. The first test attempt was interrupted by relaunching the host app; subsequent uninterrupted runs passed. No native signing or global Xcode selection changes were made.

## Editor verification (008) — 2026-11-03

Debug simulator build and the full test run passed: **116 tests in 9 suites**, including 15 `EditorSessionTests`, on a dedicated iPad (A16) / iOS 27.0 simulator so as not to disturb runs in other sessions. The tests cover save/reopen, canvas growth, undo/redo and revision, page add/delete, move/resize bounds, autosave debounce, conflicts and read-only opening. Tests that count undo steps let the run loop turn between edits, because the undo manager groups by event. Native Pencil strokes, touch arbitration, rotation, force-quit timing and the A16 owner check are **NOT RUN**. See [ticket 008](../../tickets/008-canvas-and-a4-notebook-documents.md).

## Provider spike verification — 2026-11-03

Canonical Debug build and full native test command passed: **83 tests in 7 suites**, including 20 provider test methods plus the existing scaffold/spike/command-validator/document-store tests. Parameterized cases cover status/endpoint variants. Release simulator build with `-configuration Release` passed. The [Debug screen screenshot](../../tests/evidence/007/qwen-debug.png) and synthetic equation PNG were visually inspected on the iPad (A16) / iOS 27.0 simulator. Xcode 27.0 (27A266a) was selected per command.

Provider tests use checked-in synthetic fixtures, not live recordings, and unique synthetic Keychain identities. URLProtocol tests exercise production URLSession delegate/cancellation paths without sending packets. No provider credential, real request, physical install, signing change or global Xcode-selection change was used. An earlier test-host bootstrap failure was followed by a successful complete run. See [provider implementation/evidence](../api/providers.md) for bounds, provenance, logging checks and owner test steps. Live Qwen vision/stream/cancellation remains **NOT RUN** and ticket 007 remains open.

## Library verification — 2026-11-03

The `PencilEcho` scheme now runs the hosted unit/model/service target; the dedicated `PencilEchoLibraryUI` scheme runs the two Debug-only library UI journeys. Final dedicated runs passed **141 tests in 11 suites** and **2 UI journeys** respectively. The 19 library tests include package identity/corruption, fresh-store relaunch, atomic metadata preservation/failure, open-editor guards, a 500-manifest list, image thumbnails and editor-save preview integration. UI tests use UUID-isolated temporary libraries, never owner Documents, and verify process relaunch plus cancelled/confirmed deletion and accessibility XXXL damaged-package behavior.

Both retained screenshots were visually inspected. Earlier combined failures/stalls are not counted as green; dedicated reruns completed successfully after source updates and scheme separation. Physical A16, Pencil and spoken VoiceOver acceptance remain open. See [library-009.md](library-009.md) for exact commands, screenshots and limitations.

## Rich-object verification — 2026-11-03

Ticket 011 adds native Markdown/SwiftMath rendering, a live source sheet and automatic height. The full hosted run passed **167 tests in 13 suites**, including nine rich-object tests, all 30 native expressions, one-step edit/frame undo, save/reopen and the measured-height placement regression. Three UI journeys have individual passing runs (rich-source/400% pinch, damaged-package accessibility, and library rename/relaunch/delete); the earlier combined rename failure and successful dedicated rerun are explicitly recorded in [rich-text-011.md](rich-text-011.md). Release simulator build passed. Corpus, source/preview and zoom images were retained and visually inspected. Physical A16/Pencil, owner appearance and spoken VoiceOver acceptance remain open.

## Native-provider verification — 2026-11-04

Ticket 013's full hosted run passed **181 tests in 14 suites**, including 14 parameterized native-provider test functions and the existing OpenAI/provider/settings/editor/storage regressions. Native fixtures cover Anthropic/Gemini success and errors, image/auth/schema fields, fragmented SSE, cancellation, safety, key/vision gates and generic Ask AI application. Debug test build and Release simulator build passed. The serialized Release rerun resolved an Xcode build-database lock from concurrent build attempts; it does not indicate a provider runtime defect. Commands, official contracts, test limitations and both **not verified** real-provider statuses are in [providers.md](../api/providers.md#native-anthropic-and-gemini-adapters--ticket-013). No new settings UI journey, physical A16 acceptance or live request is claimed.

## Diagram and precise-ink verification — 2026-11-05

Tickets 018 and 019 add version 3 diagram strokes, labels, a magnified focus image and page-coordinate ink. Targeted hosted runs on the iPad (A16) simulator passed the validator, converter, Feynman fixture, maze fixture, focus-image and two-image adapter tests after one limit-test correction (`1e400` overflows JSON parsing). The corrected rerun passed 40 tests in 3 suites. A full suite and a Release build were not run for these tickets. The capture grid was not added. Real-provider and physical A16 acceptance remain open. Commands and limits are in [diagrams-018-019.md](diagrams-018-019.md).
