# 002 — Xcode project scaffold

Milestone: PE-000 · Status: Resolved (2026-11-03) · Owner: Codex · Depends on: 001

## What

Create the native iPad app project with an app target and a unit-test target, plus documented build/test commands.

## Why

No native project exists. All later tickets need a buildable target and a repeatable command.

## Scope

- Project `PencilEcho.xcodeproj` (or `Package.swift` + app project; pick one and document why) at `application/`.
- App target: SwiftUI lifecycle, iPad only, deployment target iPadOS 27.0, portrait + landscape, multiple windows enabled (`UIApplicationSupportsMultipleScenes`).
- Local Swift packages or groups for logical modules:
  - `DocumentModel` (`shared/`): IDs, geometry, schema types.
  - `Services` (`service/`): persistence, AI orchestration, providers.
  - `App` (`application/`): UI, ink and object views.
- Unit-test target `PencilEchoTests` with one passing placeholder test per module.
- Placeholder home screen: "Pencil Echo" title + "New Canvas" / "New Notebook" buttons (no behavior).
- `.gitignore` entries for `DerivedData`, `xcuserdata`, `*.xcuserstate`.

## Commands to add to `AGENTS.md` (Verification Commands)

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' test
```

Adjust paths to the actual layout and record the exact working commands.

## Exclusions

No drawing, persistence, AI or third-party dependencies. No changes to `inspiration/`, `.agents/` or template tooling.

## Acceptance

- [x] Build and test commands succeed on the `iPad (A16)` simulator; output summarized in the PR or ticket notes.
- [x] App launches in the simulator and shows the placeholder screen.
- [x] `AGENTS.md` repository map and verification commands updated; `docs/project-structure/project-structure.md` updated.

## Stop conditions

Stop and report if the build needs a global `xcode-select` change, or if signing blocks the simulator build.

## Ticket 002 evidence — 2026-11-03 (Asia/Manila)

- Plan-first execution followed ticket 002 and resolved dependency 001. Chose a checked-in Xcode project with logical groups to avoid adding package/generator dependencies for the shell.
- Xcode 27.0 (27A266a), iOS 27.0 simulator, iPad (A16) `709D6F70-328D-4458-8F8A-B2C47A945A80`.
- The documented `build` command exited 0: `BUILD SUCCEEDED`.
- The documented `test` command exited 0: `TEST SUCCEEDED`; Swift Testing reported **3 tests in 3 suites passed**, no failures. The XCTest compatibility runner separately reports 0 XCTest tests; the three native placeholders use Swift Testing. These are deliberately empty discovery checks, not feature coverage.
- Installed the built app with `simctl install`, launched `com.chrixcrusher.pencilecho` with `simctl launch`, and visually inspected the [portrait screenshot](../tests/evidence/002/home-portrait.png): Pencil Echo title and New Canvas / New Notebook buttons are visible. Buttons have empty actions by design.
- Inspected the built Info.plist: expected bundle ID, `UIDeviceFamily = [2]`, minimum OS 27.0, multiple scenes enabled and all four iPad orientations present. Rotation and multiwindow interaction were not manually exercised.
- `plutil -lint` passed for the source Info.plist and project.pbxproj. Xcode emitted only the App Intents metadata-skipped warning because the shell has no AppIntents dependency.
- Context validation (`node bin/create-preset.mjs validate`) exited 1 on an existing obsolete `wiki/` path in `inspiration/public/vendor/manim-web-licenses/splaytree-README.md`. The excluded reference clone was left unchanged; this is independent of the successful native checks.
- Updated AGENTS.md, runtime-folder READMEs, project structure, technical design, testing, deployment, root README and development-plan status. No API/data contract changed. No upstream code/assets were copied and no third-party dependencies were added.
- No global Xcode selection changes, signing/team configuration changes, physical installation, provider/MCP calls or owner acceptance. PE-000 remains in progress.
- Workspace root has no Git metadata, so no diff, commit or PR was created. No scope deviations.

## Independent review — 2026-11-03 (Claude)

- Re-ran the documented `test` command: `TEST SUCCEEDED`, 3 Swift Testing tests in 3 suites passed. Earlier the same day, `build` also succeeded.
- Installed and launched `com.chrixcrusher.pencilecho` on the `iPad (A16)` simulator: the placeholder screen shows the title and both buttons, matching `tests/evidence/002/home-portrait.png`.
- Build settings match the scope: iPadOS 27.0, `TARGETED_DEVICE_FAMILY = 2`, Mac Catalyst, Designed for iPad and visionOS off, Swift 6.0, automatic signing with no team set, hosted test target. The `.gitignore` entries are present.
- No ticket corrections were needed. One stale doc line was fixed: `shared/` is no longer documentation only, because ticket 006 added `shared/schemas/canvas-commands-v1.json` (AGENTS.md, project structure, `shared/README.md`).
- Not covered, and not required by acceptance: rotation and multiwindow behavior, and a physical-device install.
- Note for 004: `application/App/Spike/` files exist, but they are not in the Xcode project yet, so they don't affect this ticket's build.

