# Pencil Echo application

Open `PencilEcho.xcodeproj` and choose the shared `PencilEcho` scheme. The app uses the SwiftUI lifecycle. The home screen is the document library (ticket 009), which opens the canvas and A4 notebook editor in `App/Editor/` (ticket 008). It targets iPadOS 27.0, iPad only, all four orientations, and multiple SwiftUI windows.

A checked-in Xcode project with logical groups is sufficient for this scaffold; no package manifest, generator, third-party dependency, or separate framework target is needed. App sources live in `App/`; the DocumentModel and Services groups reference `../shared/` and `../service/`. These are organizational groups in a single app module, not enforced Swift import boundaries. The latter groups now contain native document/package/command types and persistence/provider services.

`PencilEchoTests` is a hosted unit-test target with one deliberately empty Swift Testing placeholder per logical group. The scaffold placeholders verify test discovery only. Eleven additional Debug-only spike tests exercise geometry, transactions and lasso-handler behavior. Build/test commands and evidence are in [testing](../docs/testing/test-specification.md); personal-device signing is in [deployment](../docs/deployment/deployment.md).

In a Debug build, open **Debug → Ink + object spike (004)**. `App/Spike/` contains the disposable 4,000 × 4,000 point PencilKit/UIKit experiment. It is excluded from Release. See [the spike report](../docs/spikes/004-ink-object-layer.md) for controls, results and pending A16/Pencil acceptance.

For ticket 007, open **Debug → Qwen vision test (007)**. `App/ProviderDebug/` is excluded from Release. It uses the bundled synthetic equation and shared command schema, a selected Qwen region/model and a locally saved Keychain key. A live request requires the owner to tap Send; no provider acceptance was inferred from fixtures. See [provider evidence and steps](../docs/api/providers.md).

`App/Library/` provides the manifest-backed grid, title rename, confirmed hard delete and first-page thumbnails. Returning from the native editor refreshes the list/previews. Library and editor windows share the store and open-document claim; metadata actions are refused while another window edits the document. `PencilEchoUITests` uses Debug-only isolated temporary libraries for create/rename/open/relaunch/delete and accessibility XXXL journeys. See [009 verification](../docs/testing/library-009.md).
