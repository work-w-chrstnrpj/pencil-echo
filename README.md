# Pencil Echo

A native iPad notebook where you write with Apple Pencil and AI answers beside your ink, as editable text, math, plots and drawings.

Pencil Echo is written in Swift with SwiftUI, UIKit and PencilKit for iPadOS 27. Documents stay on the iPad with no account. AI requests go only to the provider you configure, with your own API key, or to Claude Code on your Mac through your Claude subscription.

> Based on [PenEcho](https://github.com/penecho/penecho) (AGPL-3.0-only). Pencil Echo is an independent project, not an official PenEcho release.

## Features (v0.1.0)

- **Canvas and A4 notebooks** with every PencilKit tool, page styles and autosave.
- **Ask AI and Auto answer:** pause after writing and the answer appears beside your newest ink. Circle, arrow and "why?" gestures, and context around the new ink.
- **Editable answers:** text, Markdown, LaTeX, function plots and native ink drawings, including diagram strokes (arcs, waves, arrowheads, labels) and page-precise overlays such as maze paths.
- **Agent chat** about a selection or the visible page, with answers placed as drafts you accept or discard.
- **Claude Code on your Mac** can see a shared page and place answers over your home Wi-Fi (encrypted, paired, foreground only). See [MCP](docs/api/mcp.md).
- **Providers:** Qwen, OpenAI, Anthropic, OpenRouter, Gemini, Cerebras, Groq, Hugging Face, Mistral, NVIDIA and custom OpenAI-compatible endpoints. Keys stay in the iPad's Keychain.
- **Library** with Recent, Favorites, search, sort, grid and list.
- **iPadOS 26+ design:** one Liquid Glass command bar, a floating selection bar, inspectors, and a Liquid Glass app icon.

## Requirements

- iPad on iPadOS 27 (tested on iPad A16 with Apple Pencil USB-C) and a Mac with Xcode 27.
- For AI: an API key for a supported provider, or Claude Code signed in with a Claude subscription.

## Build and install

Open `application/PencilEcho.xcodeproj`, choose the `PencilEcho` scheme and your iPad, and run. A free Apple ID (Personal Team) is enough; the build expires after 7 days. Command-line steps: [deployment](docs/deployment/deployment.md).

To use Claude Code, build the Mac helper and follow [Claude Code on the Mac](docs/deployment/deployment.md#claude-code-on-the-mac-ticket-023):

```bash
swift build -c release --package-path tools/mcp-bridge
```

## Documentation

- [Product requirements](docs/product-specification/product-specification.md)
- [Technical intent](docs/tdd/tdd.md)
- [Milestones and tickets](docs/development-plan/development-plan.md)
- [Decision record](docs/decisions.md)
- [UI style guide](docs/design/ui-style-guide.md)
- [Testing](docs/testing/test-specification.md)
- [Deployment](docs/deployment/deployment.md)
- [Changelog](CHANGELOG.md)

## License

GNU Affero General Public License v3.0 only (`AGPL-3.0-only`); see [LICENSE](LICENSE) and [NOTICE](NOTICE). Files ported from PenEcho keep a provenance header and are listed in [docs/reuse-inventory.md](docs/reuse-inventory.md). The upstream reference clone in `inspiration/` is not part of this repository.
