# Editor shell and agent chat — 020/021

Date: 2026-11-04 (Asia/Manila). Implemented; builds and native checks verified; simulator runtime execution blocked. Owner A16/Pencil/VoiceOver and real-provider acceptance remain open.

## Scope and implementation

Ticket 020 was implemented first: observable autosave state, inline rename with library title limits, document creation and current-page PNG sharing, edge-movable AI toolbar, Auto Ask/delay, documented model-specific reasoning controls, eight AI colors, per-object handwriting/rounded/system font, hand navigation, shared undo/redo, saved pattern visibility, fullscreen recovery, adaptive reusable settings, saved connections, thinking indicator at the capture region, and bundled notices. Drawing tools remain in PKToolPicker. Its reported occlusion determines toolbar clearance/edge. Existing native mixed-selection/object/page controls remain available in a horizontally scrollable row with 44-point targets.

Ticket 021 builds on that shell: a mutually exclusive chat/settings panel, compact sheets, document-local panel state, selection/visible-page context, native dictation through the keyboard, 10 completed text turns in optional chat.json, cancellable streamed message preview, validated additive-only draft placement, dashed outlines, and atomic undoable Accept all / Discard all for both objects and ink. Prior images, raw command JSON and thinking are excluded from history. New chat preserves canvas content and drafts. Auto Ask pauses while chat is open/running; handwritten and typed requests cannot overlap.

Reasoning is intentionally gated to exact documented model mappings. Current newer Claude/Gemini suggestions and unknown routers do not inherit older budget parameters. See [provider contract details](../api/providers.md). No upstream code or styles were copied for these tickets.

## Verification commands

Use per-command Xcode selection; do not change global xcode-select. A dedicated disposable A16 simulator was created as `53CEF645-055C-4946-B5DB-87E10C41094E` to avoid other sessions using the default simulator. All UI data uses a UUID-isolated temporary document library. `-chatFixture` only works in Debug with a valid isolated library ID and uses an in-process synthetic stream, without keys or network.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,id=53CEF645-055C-4946-B5DB-87E10C41094E' -parallel-testing-enabled NO test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEchoLibraryUI -destination 'platform=iOS Simulator,id=53CEF645-055C-4946-B5DB-87E10C41094E' -parallel-testing-enabled NO -only-testing:PencilEchoUITests/LibraryUITests/testEditorShellControls -only-testing:PencilEchoUITests/LibraryUITests/testCompactSettingsSheet -only-testing:PencilEchoUITests/LibraryUITests/testChatFixtureAcceptReopenAndClear test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -configuration Release -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

## Current results

- Release and final Debug arm64 simulator builds passed. Both final hosted and UI test target `build-for-testing` commands passed. Hosted runtime tests have not completed because simulator startup stalled.
- Initial simulator runs were interrupted after startup stalled. They are not passing tests. No owner documents were modified by test setup.
- Regular settings, forced compact-trait sheet and fixture-chat UI journeys are defined. Screenshots attach to the xcresult only after those journeys reach their screenshot step. Forced compact traits exercise the sheet branch; physical Split View remains a separate gate.
- An initial native macOS contract executable passed **61 assertions** against the actual repository provider/model sources and exact streamed-message parser, covering protocol reasoning mappings, multi-turn roles, complete-turn trimming, legacy settings and streamed string isolation. No network/Keychain request was made.
- The repeatable combined command is `scripts/verify-editor-chat-native.sh`. It also compiles the actual EditorSession, EditorLayout, DocumentStore and document model with macOS PencilKit, checking draft persistence and undo. Its renderer/thumbnail shims and NSBezierPath compatibility alias are explicit in `tests/native/EditorChatChecks.swift`; these cannot establish iPad rendering, lasso UI or hardware interaction. **Combined result: PASS — 80 assertions (61 provider/model + 19 PencilKit/session persistence/undo).** The initial native session harness lacked a bundle identifier and crashed inside PencilKit replica preferences (`CFEqual` with a null bundle identifier); embedding a synthetic executable Info.plist corrected the harness, and the rerun passed. This is distinct from an app failure.

## Regression coverage

These checks are defined in source; only the builds and native assertions listed above have executed successfully in this run. Hosted controller/cancellation tests and UI journeys remain unexecuted because of simulator startup stalls.

- Reasoning request mapping at Off/Low/Medium/High for all three protocols; unsupported model menu gating and legacy settings decode.
- Rename limits, metadata-only revisions, autosave/reopen, grid flag and AI appearance round trip, hand drawing disabled with scrolling/zoom retained.
- Selected versus visible context, current-image-only multi-turn native request bodies and Gemini assistant→model role mapping, request history bounds.
- Fixture answer placement as object and ink drafts; draft persistence; Accept/Discard undo; accepted ink surviving later draft discard; cancelled/late streams; stale scope rejection; complete-turn trimming; missing/malformed optional chat migration behavior; streamed string escaping without operation leakage.
- UI: Auto/Manual, pause delay, rename, saved grid visibility, fullscreen recovery, settings panel, compact sheet, chat send/accept/reopen/new chat.

## Remaining owner gates

A16 landscape/portrait and actual Split View; Apple Pencil drawing and hand-mode navigation; freely repositioning the system picker against both AI toolbar edges; VoiceOver, keyboard and large Dynamic Type interaction; a real request with supported reasoning selected; the owner incline diagram, worked descent times and one follow-up through a real provider. Simulator fixtures cannot establish provider quality, cost or hardware interaction.

No commit, push, PR, merge or device installation is implied by this implementation record. Review and live acceptance remain distinct.

## Integration notes

The shared checkout also contains concurrent 017–019 and 022 work. Three nested Swift Testing `#require` uses were flattened into intermediate values to unblock the integrated test target, and the capture image-side constant was made nonisolated for an existing nonisolated geometry helper. Those changes preserve behavior. The editor and chat changes do not revert the other ticket work. No unsupported reasoning parameter was added to newer provider models.

## Evidence and final status

`tests/evidence/020/verification.txt` and `tests/evidence/021/verification.txt` retain command/result summaries; 021 also retains the combined native check output. App screenshots could not be captured: the disposable simulator remained on its Apple boot screen. No boot screenshot is represented as an editor screenshot. The disposable simulator was shut down after the interrupted attempts; other sessions' simulators and test processes were left alone.

Both ticket implementations are reviewable. They remain in progress for simulator runtime/UI verification and the retained owner/device/provider gates. No passing full hosted suite, UI journey, visual inspection, hardware acceptance or live-provider result is claimed.
