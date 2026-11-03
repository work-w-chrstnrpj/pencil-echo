# 001 — Record toolchain, device and signing facts

Milestone: PE-000 · Status: Resolved (2026-11-03) · Owner: Owner (signing) + Claude (docs) · Depends on: none

## What

Close implementation gate 1 in `docs/decisions.md` by recording verified toolchain, device and signing facts.

## Why

Every native ticket needs a fixed SDK, deployment target, bundle ID and signing team. The docs currently say "pending".

## Known facts (inspected 2026-11-03)

- Xcode 27.0 (27A266a) at `/Applications/Xcode.app`. Active `xcode-select` is CommandLineTools; do **not** change it. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command.
- SDKs: `iphoneos27.0`, `iphonesimulator27.0`.
- Simulator: `iPad (A16)` iOS 27.0.
- Device: "iPad ni Paj", iPadOS 27.0.1, chip 8120 (A16). Previously paired; offline at inspection.

## Scope

- Signing (owner decision 2026-11-03): **free Apple ID Personal Team**. The project must cost nothing. Provisioning lasts 7 days; reinstall from Xcode to renew (documents are kept). Use only capabilities a Personal Team allows. Do not add entitlements that need a paid account.
- Choose bundle ID (e.g. `com.<owner>.pencilecho`) and deployment target **iPadOS 27.0**, device family iPad only.
- Update `docs/decisions.md` gate 1, `docs/deployment/deployment.md` readiness, and the `AGENTS.md` overview.

## Exclusions

No Xcode project creation (ticket 002). No global Xcode selection change.

## Acceptance

- [x] Signing team type, bundle ID, deployment target and device OS build recorded.
- [x] Gate 1 marked resolved with date.

## Resolution notes

Bundle ID `com.chrixcrusher.pencilecho` (owner). Device re-checked online 2026-11-03: iPadOS 27.0.1 build 24A446, Developer Mode enabled. Recorded in `docs/decisions.md`, `docs/deployment/deployment.md` and `AGENTS.md`.

