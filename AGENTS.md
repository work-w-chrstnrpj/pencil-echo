# Project Agent Rules

Source of intent: `docs/tdd/tdd.md`. Source files remain the final implementation truth.

Agents working in this repository must keep implementation and documentation changes aligned with the project goal:

```text
Build Pencil Echo, an open-source native Swift iPad workspace based on inspiration/: write with PencilKit, request AI assistance, and receive editable answers on local Canvas or A4 notebook documents.
```

## Project Overview

Pencil Echo is for anyone who wants to think and solve visually. Initial acceptance uses the owner's iPad A16 (iPadOS 27.0.1, build 24A446) and Apple Pencil USB-C. Toolchain: Xcode 27.0 with the iPadOS 27.0 SDK; deployment target iPadOS 27.0; bundle ID `com.chrixcrusher.pencilecho`; free Personal Team signing. Documents save locally without accounts. API-key AI starts with Qwen and also supports OpenAI, Anthropic, OpenRouter, Gemini, Cerebras, Groq, Hugging Face, Mistral and NVIDIA. The native shell (002) and Debug-only ink/object prototype (004) are implemented; the Qwen-first provider spike (007) is fixture verified; physical spike/live-provider acceptance and integrated product features remain pending. See `docs/decisions.md` for confirmed scope and gates.

## Detected Tech Stack

- Application/runtime: SwiftUI local library/native editor handoff in `application/PencilEcho.xcodeproj`; Debug-only UIKit/PencilKit experiment in `application/App/Spike/`; canvas and A4 notebook editors in `application/App/Editor/` (ticket 008); contained WKWebView widgets remain planned.
- Service/API layer: in-process persistence, OpenAI-compatible streaming and native Anthropic/Gemini providers; real-provider acceptance and optional paired foreground LAN MCP remain pending.
- Data store: per-document `.pencilecho` packages (JSON + PencilKit data) via `DocumentStore`, schema v1 in `docs/database/document-schema-v1.md`; keys in Keychain.
- Testing: hosted `PencilEchoTests` covers scaffold, geometry, persistence, command validation, editors, providers and AI-flow fixtures; `PencilEchoUITests` runs isolated Debug library journeys. Latest results and physical A16 acceptance limits are recorded below.
- Deployment: personal iPad installation; no required hosted backend.

## Repository Map

Update this map whenever the project structure changes.

- `application/`: `PencilEcho.xcodeproj` with shared PencilEcho scheme; `App/` contains the library HomeView and Info.plist; `App/Library/` contains the grid/model/thumbnail renderer; `App/Editor/` contains the canvas/notebook editor (ticket 008); `App/Spike/` contains the Debug-only ink/object prototype; `App/ProviderDebug/` contains the Qwen Debug screen; `App/RichText/` holds native Markdown/SwiftMath rendering and the source editor (011); `App/Resources/` holds the bundled synthetic equation and third-party notices.
- `application/App/AskAI/`: scoped handwriting requests, editor shell/adaptive panels, typed agent chat, streaming reply preview and editable draft controls (020/021). `application/App/Settings/` contains reusable provider and canvas preferences.
- `service/`: Services logical Xcode group; in-process Swift services. `Persistence/DocumentStore.swift` saves and loads document packages (ticket 005); `Providers/` implements OpenAI-compatible and native Anthropic/Gemini streaming adapters, the protocol factory, presets/settings and Keychain store; `AI/` handles PNG data URLs.
- `shared/`: DocumentModel logical Xcode group; future Swift IDs, geometry and schema types. `Document/` holds the document package types and migrator (ticket 005); `CanvasCommands/` holds the AI answer types and `CommandValidator`; `schemas/canvas-commands-v1.json` is the provider JSON Schema (ticket 006).
- `tests/`: `PencilEchoTests/` native tests, `PencilEchoUITests/` isolated Debug library journeys, `fixtures/documents/` document packages and their generator, `fixtures/providers/` synthetic SSE/status fixtures, `fixtures/latex/` 30 math expressions, `evidence/002/`, `evidence/004/`, `evidence/007/` and `evidence/009/` simulator screenshots and copied template-tooling tests at the root. `tests/native/` and `scripts/verify-editor-chat-native.sh` provide simulator-independent provider/model checks with explicit rendering shims.
- `docs/`: project intent, contracts, architecture, operations, and quality documentation.
- `inspiration/`: separate upstream reference clone; reuse requires provenance and applicable notices (`docs/reuse-inventory.md`).
- `bin/`, `lib/`, `scripts/`, `package.json`: copied AI-template tooling, not the Swift runtime.
- `.agents/`: canonical reusable AI roles, skills, overlays, workflows, and tool policies.
- `.ai/`: context routing, maps, prompt recipes, and generated-index guidance.
- Tool adapters: `.claude/`, `.codex/`, `.cursor/`, `.github/`, `.opencode/`, and other generated folders expose canonical assets in each tool's expected format.

## Core Operating Rules

- Prefer project docs as the source of product intent.
- Prefer exact source files as the source of implementation truth.
- Use maps, indexes, graphs, and summaries only for discovery.
- Read exact files before changing them.
- Make small, reviewable edits that follow the project structure.
- Run relevant verification before claiming success.
- Ask for approval before destructive, high-risk, production, secret, or migration operations.

## Documentation Rules

- Keep `docs/tdd/tdd.md` canonical for technical intent.
- Update API, data, diagram, testing, deployment, and project-structure docs when behavior or architecture changes.
- If work is tracked in `docs/development-plan/development-plan.md`, update the matching status.
- Do not add project-specific requirements to reusable template files unless the project has adopted them.

## Security Rules

- Do not commit secrets, tokens, private keys, credentials, or production configuration.
- Do not log sensitive input, provider responses, credentials, or private user data.
- Validate input at trust boundaries.
- Prefer least privilege for accounts, tokens, services, and automation.

## Upstream Reuse Rules

- Port from `inspiration/` only files listed in `docs/reuse-inventory.md`. To port a new file, add its row first.
- Each translated Swift file starts with a provenance header, one line per source file: `// Ported from PenEcho inspiration/<path> @ 341e34d (<upstream license>).`
- Embedded upstream files keep their license file next to them. Never copy PenEcho brand assets or names.
- Never edit `inspiration/`.

## Git And PR Rules

- Check `git status` before major edits.
- Do not revert user changes unless explicitly asked.
- Keep commits scoped and explain verification in PR notes.
- Avoid force push, reset, clean, or destructive history operations without explicit approval.

## Canonical AI Structure

Canonical reusable AI assets live in `.agents/`:

- `.agents/roles/`: 9 role owners.
- `.agents/skills/`: reusable workflow skills only.
- `.agents/overlays/`: Mentor and Coach overlays.
- `.agents/workflows/`: multi-role workflows.
- `.agents/tools/`: context, verification, adapter, and tool policies.

Tool-specific folders are generated adapters, not source of truth. Update canonical files first, then run `node bin/create-preset.mjs sync` (or `pwsh scripts/sync-ai-adapters.ps1`).

## Overlay Usage

Use overlays to change response style without changing work ownership.

Examples:

- `Mentor ELI12: Explain this architecture.`
- `Coach: Critique this plan.`
- `Software Engineer + Mentor: Explain this feature design.`
- `Backend & Database Engineer + Mentor: Explain this API design.`
- `System Architect + Coach: Challenge this architecture proposal.`

## AI Role Usage Guide

Portable role prompts live in `.agents/roles/`. Tool-specific generated adapters live under `.claude/agents/`, `.codex/agents/`, `.cursor/rules/`, `.github/agents/`, and `.opencode/agents/`.

- Software Engineer: general coding, fullstack implementation, end-to-end features, refactoring, and integration.
- System Architect: architecture, module boundaries, dataflow, and technical risk.
- Product & Planning Manager: requirements, acceptance criteria, task breakdown, dependencies, and progress coordination.
- Frontend UI/UX Developer: UI, routing, state, accessibility, client behavior, and frontend tests.
- Backend & Database Engineer: APIs, services, validation, auth, persistence, integrations, jobs, queues, and data ingestion.
- DevOps Engineer: CI/CD, deployment, runtime config, automation operations, monitoring, and releases.
- Security Engineer: secrets, auth, authorization, dependency risk, unsafe inputs, logging, and sensitive workflows.
- SQA Engineer: test plans, manual cases, automated tests, regressions, acceptance verification, and bug reports.
- Technical Documentation Specialist: README, API docs, setup, onboarding, operations, workflow, integration, and changelog docs.

## Skill Usage Guide

Create or keep a standalone skill only when it defines a reusable workflow with clear inputs, steps, boundaries, and outputs.

Do not create standalone skills for every role capability. Put domain-specific capability guidance inside the owning role file under `Embedded Capability Playbooks` or reference playbooks.

Reusable skills live in `.agents/skills/`. Tool-specific skill copies are generated for Claude, Cursor, GitHub Copilot, OpenCode, and Windsurf; Codex and Antigravity use `.agents/skills/` directly. Choose the smallest skill that matches the task, then read exact source files before editing.

## Verification Commands

Ticket 009 (2026-11-03): library/native editor handoff and metadata safety verified; 141 hosted tests and 2 isolated UI journeys passed in separate shared schemes. `PencilEchoLibraryUI` runs the UI journeys; exact commands and physical-acceptance limits are in `docs/testing/library-009.md`.

The separate PencilEchoLibraryUI scheme runs the Debug-only library UI journeys; PencilEcho retains the hosted unit/model tests. They create/delete only synthetic data in a UUID-isolated temporary library. `docs/testing/library-009.md` documents separate unit/UI commands and current results; physical A16/Pencil/VoiceOver acceptance remains separate.

Ticket 007 verification (2026-11-03): Debug/Release simulator builds passed; full suite passed 83 tests in 7 suites, including provider/Keychain/URLSession fixtures; Qwen Debug screen visually checked. Real Qwen requests remain NOT RUN. See `docs/api/providers.md`.

Run from the workspace root. Use per-command Xcode selection; never change global `xcode-select` for this project.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

Verified 2026-11-03 on iPad (A16) / iOS 27.0: build succeeded; three Swift Testing placeholders passed; app launched and the placeholder screen was visually checked. See ticket 002 for evidence.

Ticket 004 verification (2026-11-03): Debug/Release simulator builds passed; 14 tests passed (11 spike tests plus 3 discovery placeholders); three zoom screenshots and both z-orders inspected. Physical A16/Pencil acceptance and Owner + Claude review are pending. See `docs/spikes/004-ink-object-layer.md`.

The scaffold tests are three intentional placeholders for logical groups, with no feature assertions. The Debug-only spike tests exercise geometry, transactions and deterministic lasso-handler states; they do not establish touch/Pencil hardware behavior. Root npm tests exercise template tooling, not app behavior.

- `node bin/create-preset.mjs validate`: context structural validation only. Currently fails on an existing obsolete `wiki/` reference inside excluded `inspiration/`.
- Real-provider/MCP/device acceptance: not run.

Do not claim implementation from planned docs or infer device acceptance from builds. Keep provider integrations, MCP clients and hardware claims independently verified. Preserve owner documents on installation. No background MCP availability guarantee. Read `docs/decisions.md` before selecting implementation scope.

Ticket 011 verification (2026-11-03): native Markdown/SwiftMath source editing, persistence, undo/reflow and 30-expression corpus are implemented; 167 hosted tests passed. Rich-source/400% pinch and the two library UI journeys have individual passing runs; the report distinguishes the failed combined rename run from its corrected dedicated rerun. Release simulator build passed. `docs/testing/rich-text-011.md` records renderer bounds and retained visuals. These results do not establish physical A16/Pencil/VoiceOver or real-provider acceptance.

Ticket 013 verification (2026-11-04): native Anthropic Messages/Gemini streaming and common factory integration are implemented; 181 hosted tests in 14 suites passed, including native protocol/key/safety/cancel and generic Ask AI fixtures. Debug test and Release simulator builds passed. Native model suggestions are static, unknown-model vision is opt-in, and keys remain endpoint-scoped. Both real-provider runs remain **not verified**; ticket 013 stays in progress for owner acceptance. See `docs/api/providers.md` for current official contracts and limits.

Tickets 018 and 019 verification (2026-11-05): version 3 diagram strokes, labels, focus image and page-coordinate ink are implemented. Targeted iPad (A16) simulator runs passed the validator, converter, Feynman and maze fixtures, focus-image capture and two-image adapter tests. One overflow assertion was corrected (`1e400` is malformed JSON) and the rerun passed 40 tests in 3 suites. No full suite, Release build, real-provider request or physical acceptance is claimed. The capture grid was not added. See `docs/testing/diagrams-018-019.md`.

Tickets 020/021 verification (2026-11-04): editor shell, adaptive settings and typed chat/drafts implemented. Debug/Release arm64 simulator builds and both hosted/UI test-target builds passed. `scripts/verify-editor-chat-native.sh` passed 80 assertions (61 provider/history/parser + 19 native PencilKit/session persistence/undo), with explicit rendering/thumbnail shims. Hosted runtime and UI journeys were blocked by simulator boot stalls; no full-suite or screenshot acceptance is claimed. Physical A16/Pencil/VoiceOver and real-provider gates remain open. See `docs/testing/editor-shell-and-chat-020-021.md`.
