# Editable Markdown and LaTeX objects — ticket 011

Implementation date: 2026-11-03. Simulator verification is recorded below; physical A16/Pencil and spoken VoiceOver acceptance remain separate owner gates.

## Behavior and renderer decision

Use the editor's function button → Markdown or Formula to create an object. Double-tap an existing text/Markdown/formula object to open a multiline source sheet with a live preview. Save commits source, measured height and revision in one undo transaction. Cancel discards the sheet's draft. The width resize handle reflows Markdown; rich object height follows content, bounded by the page. Existing plain text objects keep their manually sized frame. No document schema migration is required: `source`, `type` and `frame` remain schema v1 fields, and rendered images are derived caches only.

Markdown uses Foundation `AttributedString(markdown:)`, mapping heading, paragraph/list and inline bold/italic/code intents to native attributed text. A bounded delimiter scanner separates `$inline$` and `$$display$$` formulas, preserving escaped dollars, code spans/fences and unclosed delimiters. Images, HTML, links and code are never fetched or executed. Inline formulas become native text attachments; block formulas receive separate paragraphs. VoiceOver labels expose the complete stored source, including commands and Markdown syntax.

[SwiftMath](https://github.com/mgriebling/SwiftMath/tree/1.7.3) 1.7.3 is an exact-version Swift Package dependency pinned to `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`. It renders offline through native font/typesetting APIs. The initial corpus evaluation found that the AMS macro `\iint` was unsupported. A rendering-only expansion to `\int\!\!\int` covers it without changing source. All 30 corpus expressions now render natively, including fractions, integrals, roots, matrices, cases and aligned equations. No MathJax/KaTeX or web renderer is needed for this corpus. This is a bounded LaTeX math subset, not a TeX document engine; unknown commands and literal non-ASCII math take the visible fallback path. Unicode Markdown text is supported; math symbols can use commands such as `\alpha`.

SwiftMath is MIT; its notice is bundled in `App/Resources/ThirdPartyNotices/SwiftMath-LICENSE.txt`. Its unmodified `mathFonts.bundle` includes its own OFL/GUST font notices, retained by Swift Package Manager. No paid dependency or backend is required. Design reference: `inspiration/src/server/typeset.js` (prompt policy) and `inspiration/public/mathjax-config.js` (SVG font-cache settings). Neither reference file was copied or translated.

The canvas retypesets attachments after zoom ends at screen density × zoom (up to 8 pixels per document point on the 2× A16 simulator at 4× zoom). Native text is redrawn at the same bounded density. Thumbnails and captured AI regions use the same rich renderer. Measurements occur before new AI answer placement so measured additions participate in overlap checks and page flow.

## Limits and fallback

Stored source retains the schema's 100 KB limit. Rendering is capped at 32 KB per object, 128 segments, 32 formulas, width 24–2,048 pt and measured height 2,048 pt. One formula is capped at 8 KB, 32 brace levels, 128 commands and 64 alignment separators; raster output is capped at 4,096 pixels per axis / 4,194,304 pixels. Formula images fit their object width without wrapping. Limits or parse failures show raw source and an orange warning badge; a limit fallback displays the first 2,000 characters on canvas while the editor and accessibility label retain the full source. Page clipping also displays a warning. No source is deleted or rewritten by fallback. Limits are defensive bounds, not measured physical A16 performance guarantees.

## Verification

Corpus: `tests/fixtures/latex/corpus.json`, 30 original synthetic expressions. Initial unsupported macro: `double-integral` (`\iint`), covered by the native expansion above. Remaining corpus failures: none. Invalid/unknown commands, unbalanced/nested input and large source have dedicated fallback checks.

`RichTextTests` covers delimiters/escaping/code/unclosed input, heading/bold/list styling, native corpus, raw-source failures, full accessibility source, 4× formula pixel density, automatic height after width changes, one-step source/frame undo/redo, revision, atomic save and source/frame reopen. The UI journey uses a UUID-isolated temporary library and exercises creation, live preview, Save, undo/redo, Cancel, Done, library reopen and source reopening by double-tap.

Commands (from workspace root, Xcode 27.0, iPad A16 / iOS 27.0 simulator):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEchoLibraryUI -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Dedicated library rerun after restoring its original field-entry helper:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEchoLibraryUI -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -only-testing:PencilEchoUITests/LibraryUITests/testCreateRenameReopenRelaunchAndConfirmedDelete test
```

Final hosted run: **167 tests in 13 suites passed**. The nine rich-object tests include the 30-expression corpus; the AI suite also verifies that measured formula height participates in collision avoidance. **Release simulator build passed** for arm64 and x86_64. It retains the pre-existing editor background-save `taskId` capture warning and AppIntents metadata-skipped warning; no new renderer warning remains.

All **three UI journeys have passing runs**: the rich-source/400% pinch journey and damaged-package/accessibility journey passed in the final combined run; the existing create/rename/relaunch/delete journey passed in its subsequent dedicated run with its original field-entry helper restored. The combined run itself failed that rename case while its temporary Command-A helper was in use, and is not counted as a fully passing run. Earlier rich-source test failures came from test caret assumptions, and the orientation defect was corrected before retained visual evidence. A failed floating-point equality regression was changed to a 0.01 pt geometry tolerance before the passing hosted run.

Retained and visually inspected:

- [30-expression native corpus](../../tests/evidence/011/native-corpus.png)
- [Edited source and live native preview after library reopen](../../tests/evidence/011/source-preview.png)
- [Canvas after an asserted pinch to 400% zoom](../../tests/evidence/011/canvas-4x.png)
- [Native fraction at 8 pixels per document point](../../tests/evidence/011/math-4x.png)

Local run logs: `/tmp/pencilecho-011-final-unit.log`, `/tmp/pencilecho-011-final-release.log`, `/tmp/pencilecho-011-ui-complete.log` and `/tmp/pencilecho-011-ui-library-regression.log`. Test-result bundles remain in Xcode DerivedData. The UI libraries are synthetic temporary packages, and the screenshot sources contain no owner documents or provider data. Physical Pencil interaction, A16 memory/latency, owner appearance and actual VoiceOver speech are not established by simulator checks. No real provider request was needed for this ticket.
