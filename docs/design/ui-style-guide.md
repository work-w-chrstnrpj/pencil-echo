# Pencil Echo UI style guide (tickets 024–027)

Owner: Claude (senior). Every UI ticket follows this page. When this page and a ticket disagree, ask Claude before coding.

Target: iPadOS 27, SwiftUI first, Apple Human Interface Guidelines with the Liquid Glass design language (introduced in iPadOS 26 and continued in 27). Use system components and let the system draw glass; never imitate it.

## 1. Principles

1. **Content first.** The page and the user's ink are the content. Controls float above it in the system's glass layer. Never put glass, tints or shadows on the page itself.
2. **One clear hierarchy.** One row of controls per edge. Per bar, at most one prominent action. Everything secondary goes into a menu.
3. **No duplicates.** Each command lives in exactly one place, plus its keyboard shortcut and context menu. Apple's tool picker already has pens, eraser, lasso, ruler, colors, undo and redo: don't repeat them.
4. **Plain words.** Sentence-case labels, verbs for actions ("Ask AI", "Insert"), nouns for places ("Settings"). No internal jargon ("Manual", "MCP", "fixture") in the UI.
5. **Show state with symbol + text.** Never color alone.

## 2. Layout and layers

| Layer | What | How |
|---|---|---|
| Content | Page, ink, objects, thumbnails | Plain backgrounds; `Color(.systemBackground)` / page colors |
| Controls | Navigation bars, toolbars, inspectors, popovers, floating bars | System `.toolbar`, `.inspector`, `.popover`, `.sheet`; glass comes from the system |
| Overlays | Short status cards (Ask AI review, errors, Claude Code banner) | One small glass card or capsule, top or bottom center, auto-dismiss where possible |

- **Toolbars:** use SwiftUI `.toolbar` with `ToolbarItemGroup` and `ToolbarSpacer(.fixed)` / `ToolbarSpacer(.flexible)` to form groups. No horizontally scrolling toolbars. No custom toolbar backgrounds.
- **Group size:** 2–4 related items per group. At most **8 visible top-level items** in a regular-width bar; at compact width the system overflow menu takes the rest (`ToolbarItem(placement:)` + `.toolbarTitleMenu` / menus).
- **Floating controls in content:** wrap related custom controls in one `GlassEffectContainer` and give each a `.glassEffect()` (or use `.buttonStyle(.glass)`); never nest glass in glass.
- **Prominent action:** `.buttonStyle(.glassProminent)` (in bars) or `.borderedProminent` (in forms/sheets). One per surface.
- **Side panels:** `.inspector(isPresented:)` on the trailing edge. It becomes a sheet automatically at compact width. One inspector at a time.
- **Sheets:** `NavigationStack` + `Form`, `.presentationDetents` where content is short, `Done` as `.confirmationAction`, `Cancel` as `.cancellationAction`.
- **Popovers:** short tasks only (a toggle, a status, a few rows). Anything longer is a sheet.

## 3. Tokens

Use these values; don't invent new ones.

| Token | Value | Use |
|---|---|---|
| Spacing | 4, 8, 12, 16, 20, 24, 32 | Stacks, padding, grids |
| Corner radius | 8 (small chips), 12 (rows, thumbnails in lists), 16 (cards), Capsule (pills, banners) | Always `style: .continuous` |
| Touch target | ≥ 44 × 44 pt | Every tappable control |
| Hairline | `Divider()` or `.separator` color | Never custom gray lines |
| Card shadow | none (glass and contrast carry depth) | Library cards use a 1 pt `.separator` stroke instead |

- **Typography:** system text styles only (`.largeTitle` … `.caption2`) with Dynamic Type. No fixed font sizes in chrome. The handwriting font stays only for AI answers on the page. Monospaced (`.system(.body, design: .monospaced)`) only for commands and codes.
- **Color:** semantic colors only (`.primary`, `.secondary`, `.tint`, `.red` for destructive, `.green` for "connected", `.orange` for "needs attention"). The app tint is the system accent; don't hard-code blue. No hex colors in chrome.
- **Symbols:** SF Symbols, always inside `Label` (so VoiceOver and the overflow menu get text). `.symbolRenderingMode(.hierarchical)` for status symbols. Use `.symbolEffect` only to confirm an action (for example `.bounce` on Copy), never in a loop.
- **Motion:** system animations (`.default`, `.snappy`). Respect Reduce Motion (`@Environment(\.accessibilityReduceMotion)`); no custom animation longer than 0.35 s.

## 4. Accessibility (all tickets)

- Every control has an `accessibilityLabel` (from its `Label`), a hint when the effect isn't obvious, and a value for toggles and modes.
- Works with VoiceOver, Full Keyboard Access and a hardware keyboard. Primary actions have shortcuts (`.keyboardShortcut`).
- Dynamic Type up to AX3 in chrome without clipping: text wraps, toolbars overflow into menus.
- Pointer: system hover effects on buttons (`.hoverEffect()` for custom views).
- Contrast: don't put `.secondary` text on glass over busy content; use `.primary`.
- Keep existing `accessibilityIdentifier`s; UI tests depend on them. New controls get identifiers named `area-thing` (for example `editor-insert-menu`).

## 5. Writing

- Sentence case: "Ask AI", "Answer automatically", "Share with Claude Code".
- Status lines are short: "Saved", "Saving…", "Asking…", "Answer placed", "Claude Code connected".
- Errors say what happened and what to do: "Couldn't reach the AI provider. Check your connection and try again."
- Destructive actions name the thing: "Delete page 3", "Discard 2 drafts".

## 6. Don't

- Two rows of commands, scrolling toolbars, or a button that moves the toolbar.
- Repeating tool picker controls (undo, redo, lasso, colors) in our bars.
- Custom glass (`.ultraThinMaterial` cards pretending to be glass), custom blur stacks, drop shadows on chrome.
- Debug or developer UI in any build users see.
- Color-only state, icon-only buttons without labels, fixed font sizes.

## 7. App icon

`application/App/Resources/AppIcon.icon` is an Icon Composer document (Liquid Glass, iPadOS 26+), set as the app icon with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Previews: `docs/design/icon/` (default, dark, tinted).

- **Story:** an Apple Pencil draws a hand-drawn annotation loop; the loop's echoes ripple outward; a gold AI sparkle sits inside the loop. Pencil, echo, annotation, AI.
- **Layers:** three glass groups (sparkle, pencil, annotation with two echo arcs at 55 % and 30 % opacity) on an indigo-to-blue linear gradient. The system renders light, dark, clear and tinted appearances from these layers.
- **Original artwork:** no upstream PenEcho artwork, name or logo is used.
- **Changing it:** edit `scripts/make-app-icon.py` and run `python3 scripts/make-app-icon.py application/App/Resources/AppIcon.icon` (delete the old `.icon` folder first), or open the `.icon` in Icon Composer (Xcode → Open Developer Tool). Check a rendition with `ictool` (inside Icon Composer.app) before committing.
