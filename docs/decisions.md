# Decisions and implementation gates

Status: REQUIREMENTS_CONFIRMED_WITH_GATES
Updated: 2026-11-03 (Asia/Manila)

## Owner decisions

- Product: Pencil Echo; private, experimental project with no public source or build distribution planned (owner, 2026-11-03), personal installation, iPad only, English, no target date.
- Initial hardware: iPad A16 and Apple Pencil USB-C; owner reports iPadOS 27. Support available hardware capabilities; no requirements for Pro-only Pencil controls. No finger drawing.
- Native SwiftUI/UIKit and PencilKit. Embedded web surfaces accepted for widgets, with native main interaction.
- Separate Canvas and A4 notebook document types. Notebook contains multiple pages. Optional blank/lined/dotted/grid backgrounds.
- Ink, text, images, Markdown, formulas, plots, editable diagrams, selection of ink and objects, undo/redo.
- AI provider choices (updated 2026-11-03; GitHub Models dropped by the owner on 2026-11-03 after GitHub retired it on 2026-07-30): **Qwen (Alibaba Cloud Model Studio) first**, then OpenAI, Anthropic, OpenRouter, Google Gemini, Cerebras, Groq, Hugging Face, Mistral and NVIDIA. Model selection and custom endpoints; image requests need a vision-capable model and never fall back to a text-only model; keys in Keychain; no silent provider failover.
- Manual AI plus opt-in suggestion popups initially. Suggestions execute only on tap. Optional automatic solving later, off by default.
- Selected images/text may be sent to the chosen provider. Lasso context with small margin; otherwise viewport; whole-document scope explicit.
- Apply valid AI additions automatically while preserving original work. Replace/erase only on explicit instruction. Each AI operation is one undo action. Changed target content requires review.
- Answer placed near the problem using available space. Text/formulas/diagrams remain editable; diagrams support node/connector edits and AI refinement.
- Local documents without accounts; no desktop format compatibility or cloud sync requirement. Exported files suffice for sharing.
- Library includes projects/folders, tags, bookmarks, search, reusable independent cards linked back to source, trash, autosave, bounded history, backup/restore.
- Editable app document format, PDF/PNG export, image/PDF import; imported PDF pages become annotatable A4 notebook backgrounds. SVG/Markdown export later where faithful.
- Manual backup archives initially; automatic backup to a chosen Files location deferred.
- Cost (owner, 2026-11-03): development must be free. Sign with a free Apple ID Personal Team (7-day provisioning, renewed by reinstalling from Xcode). No paid Apple Developer Program, paid services or paid dependencies. AI usage relies on the owner's own keys, preferably on free tiers.
- App identity (owner, 2026-11-03): bundle ID `com.chrixcrusher.pencilecho`; deployment target iPadOS 27.0; device family iPad only.
- Upstream reuse (owner override, 2026-11-03): code, prompts, schemas and assets in `inspiration/` may be copied or ported to Swift for this private experiment. Record provenance (upstream path + commit) in copied files. AGPL-3.0 and trademark obligations apply again if the project or a build is ever shared or published.
- Chat agent and opt-in, paired LAN MCP access while app is active; selected documents only. Candidate clients: Codex, Claude Code, Cursor; owner uses all three.
- Widgets/quizzes/simulations later; 3D gated on A16 prototype. Offline widget operation by default; no API keys or unrestricted document access; internet permission scoped separately.
- Offline drawing/edit/search/export; AI connectivity errors preserve request intent and offer manual retry.
- Portrait/landscape, supported multitasking, multiple windows, keyboard/trackpad, VoiceOver, Dynamic Type. No document locking requirement.

## Implementation gates

These are engineering investigations, not unapproved product scope.

1. **Resolved 2026-11-03.** Verify installed SDK, deployment target and physical device OS compatibility. Record actual device build and minimum supported OS; do not infer SDK availability from the reported OS number.
   - Xcode 27.0 (27A266a) at `/Applications/Xcode.app`, used via per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; global `xcode-select` stays on CommandLineTools.
   - SDKs: `iphoneos27.0`, `iphonesimulator27.0`. Simulator: `iPad (A16)` iOS 27.0 (`709D6F70-328D-4458-8F8A-B2C47A945A80`).
   - Device: "iPad ni Paj", iPad (A16) `iPad15,7`, iPadOS 27.0.1 build 24A446, paired, Developer Mode enabled (`devicectl`, 2026-11-03).
   - Deployment target / minimum supported OS: iPadOS 27.0. Bundle ID `com.chrixcrusher.pencilecho`. Signing: free Apple ID Personal Team; no entitlements that need a paid account.
2. Prototype PencilKit ink plus editable object layers with synchronized zoom, lasso, page coordinates and undo. Measure memory/latency on A16; establish tested document limits.
3. Specify exact versioned file schema, migrations, atomic save/recovery, cross-window revision rules, history retention and backup limits before persistence implementation.
   - v1 package, revision, atomic save/load, limits and migration hook specified 2026-11-03 (`docs/database/document-schema-v1.md`); implemented the same day (ticket 005). History retention, trash and backup limits pending (PE-004).
4. Verify each provider's image, streaming, structured output, authentication and error contracts against current official documentation. Do not assume shared endpoint semantics.
   - Qwen documentation checked and generic adapter fixture-tested in 007 (2026-11-03), with Debug/Release simulator builds and full-suite tests. See `docs/api/providers.md`. Owner real Qwen vision acceptance and other providers remain open.
5. Select supported MCP transport/authentication through client capability checks; test Codex, Claude Code and Cursor independently. No compatibility guarantee before evidence.
6. Define bounded AI command schema and widget permissions/resource limits before executing generated content. Verify no overwrite on stale revisions.
   - AI answer schema specified 2026-11-03 (`docs/api/canvas-commands-v1.md`); validator and tests implemented the same day (ticket 006). Widget permissions/resource limits pending (PE-006).
7. Copying from `inspiration/` is approved for private use. Keep a provenance record of reused upstream material; before any sharing or publication, resolve AGPL-3.0 licensing and a distinct product name. Template MIT metadata is not authoritative.

## External evidence

- PencilKit: https://developer.apple.com/documentation/pencilkit/pkcanvasview
- Background lifecycle: https://developer.apple.com/documentation/Xcode/configuring-background-execution-modes
- Web content: https://developer.apple.com/documentation/webkit/wkwebview/

External documentation supports feasibility; successful builds and physical acceptance remain separate gates.
