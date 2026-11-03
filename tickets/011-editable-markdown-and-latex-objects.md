# 011 — Editable Markdown and LaTeX answer objects

Milestone: PE-002 · Status: Resolved on simulator (2026-11-03; physical acceptance pending) · Owner: Codex · Depends on: 004 (008 for integration)

## What

Object types that render Markdown text and LaTeX formulas on the canvas and can be edited by the user afterward.

## Why

AI answers must remain editable, not flattened into ink or images.

## Scope

- **Markdown object:** render with `AttributedString(markdown:)` (headings, bold/italic, lists, inline code). Inline `$...$` and block `$$...$$` math rendered via the LaTeX renderer below.
- **LaTeX object:** native renderer. Evaluate SwiftMath (MIT) as a Swift Package; if it fails common cases, fall back to MathJax/KaTeX in an offscreen `WKWebView` snapshot. Document the choice and the tradeoffs. See `inspiration/src/server/typeset.js` and `public/mathjax-config.js` for upstream's approach.
- **Edit:** double-tap opens a source editor sheet (text field + live preview); Save updates `source` as one undo step and bumps `revision`.
- Auto-size height to content at a fixed width; user can resize width.
- Render failure shows the raw source with a warning badge, never crashes.
- VoiceOver reads the source text (or a spoken-math approximation if the renderer provides one).

## Exclusions

Plots, diagrams, images from AI, rich text toolbar.

## Acceptance

- [x] Test corpus (`tests/fixtures/latex/`) of ~30 expressions (fractions, integrals, matrices, aligned equations) renders without error, or failures are listed.
- [x] Edit → save → reopen preserves the edited source.
- [x] Rendering at 4× zoom stays sharp (vector or re-rendered at zoom).
- [x] Unit tests for Markdown/math splitting.

## Implementation and verification — 2026-11-03

Executed against this ticket (Mode A). `App/RichText/` implements the source splitter, native Foundation Markdown/SwiftMath renderer, zoom-aware object view and multiline draft editor. The function menu creates Markdown/formula objects; double-tap opens source. Save commits source and measured height as one revision/undo step, Cancel keeps the document unchanged, and width resize reflows height. Plain text remains editable. Native rich rendering is shared with thumbnails and AI-region capture; new AI additions are measured before overlap checks. Storage schema remains v1.

SwiftMath 1.7.3 is pinned and its MIT/font license notices are retained in the built app. The initial `\iint` gap is covered by a rendering-only macro expansion; all 30 checked-in corpus expressions pass, including matrices and aligned equations. No MathJax fallback was necessary. Unsupported input/limits expose raw source and warning badges; full source remains in storage and accessibility labels. Exact limits and the renderer decision are in [the evidence report](../docs/testing/rich-text-011.md).

The full hosted suite passed **167 tests in 13 suites**, including nine rich-rendering tests and an AI placement collision regression. The isolated rich-source UI journey passed Save, one-step undo/redo, cancelled draft, library reopen, source double-tap and a pinch to **400% zoom**. Retained corpus, source/preview, 4× canvas and 8-pixels-per-point formula images were visually inspected. Release simulator build passed. Earlier test failures (caret positioning, pixel orientation and exact floating-point comparison) were corrected and are not counted as passing runs. No owner data, provider credentials, upstream files, signing settings or global Xcode selection were changed.

Physical A16/Pencil interaction, owner appearance, memory/latency and spoken VoiceOver remain unverified. This resolves the ticket's simulator checks and does not close PE-000/PE-001/PE-002's hardware or live-provider gates. The workspace root has no Git metadata, so no commit or PR was created.
