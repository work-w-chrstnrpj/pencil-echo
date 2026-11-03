# Personal installation and operations

Status: PLANNED — no signed Pencil Echo build exists.

Initial deployment: personal installation on owner's iPad A16/USB-C Pencil. Private, experimental project: no public source or build distribution is planned (owner, 2026-11-03). App Store/TestFlight and hosted infrastructure are outside current delivery scope.

## Readiness

Confirmed 2026-11-03 (ticket 001, `docs/decisions.md` gate 1):

| Item | Value |
|---|---|
| Xcode / SDK | Xcode 27.0 (27A266a); `iphoneos27.0`, `iphonesimulator27.0` |
| Device | iPad (A16) `iPad15,7`, iPadOS 27.0.1 (24A446), Developer Mode enabled |
| Deployment target | iPadOS 27.0, iPad only |
| Bundle ID | `com.chrixcrusher.pencilecho` |
| Signing | Free Apple ID Personal Team |
| Entitlements | None beyond what a Personal Team allows |

Do not change global Xcode selection; prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. `application/PencilEcho.xcodeproj` now provides the shared `PencilEcho` scheme (ticket 002). Simulator commands are in `docs/testing/test-specification.md`. No physical-device installation was performed for this scaffold. Select the owner's Personal Team locally in Xcode before a device build; no team ID or credentials are stored in the project.

Build exact reviewed source, run available native checks, install in place preserving documents, launch and perform device smoke checks. Never uninstall or erase owner data as a routine installation step. Preserve a backup/recovery reference before migration. Signing: free Apple ID Personal Team (owner decision 2026-11-03). Builds expire after 7 days; renew by rebuilding and installing from Xcode over the existing app, which keeps documents. Avoid capabilities unavailable to Personal Teams (e.g. iCloud/CloudKit, push notifications).

Provider credentials are configured locally in the app and held in Keychain. No app account or backend deployment required. Network access is needed for remote AI; local-network permission is required for optional LAN MCP. Foreground MCP availability is not a background service guarantee.

## Publication and recovery

Before public source/build publication, inventory reused upstream material, retain applicable notices and resolve final application licensing. Use distinct Pencil Echo identity. Template MIT/package metadata is not evidence of app-wide licensing.

Define rollback against document schema compatibility; never install an older build over migrated documents without a supported recovery path. Keep backup archives and migration fixtures. App-specific logging excludes credentials, prompts and user content by default.

## Toolchain inspection, 2026-10-12

Full Xcode at `/Applications/Xcode.app` reports Xcode 27.0, build 27A266a, when invoked with a per-command DEVELOPER_DIR. Active shell selection is `/Library/Developer/CommandLineTools`; global selection was not changed. SDK inventory and device compatibility were verified on 2026-11-03 (see Readiness).

## Qwen Debug verification (007)

Build Debug and open Debug → Qwen vision test (007); this screen is excluded from Release. Save a region-specific key locally in the masked field, then explicitly send the bundled synthetic equation. Never include credentials or raw provider output in deployment notes. The simulator fixture suite and Debug-screen launch passed; a real Qwen request and physical installation were not performed. Owner steps and the live-provider evidence gate are in `docs/api/providers.md`.

## Install on the owner's iPad (verified 2026-11-03)

The first device install was done from the command line, signed with the free Personal Team (`LMHJKZ2N43`) and passing the team at build time, so the project file has no team set. The app was installed over any existing copy (no uninstall) and launched on "iPad ni Paj". Run from the repository root with the iPad connected and unlocked:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -configuration Debug -destination 'id=00008120-0014354C112B601E' -derivedDataPath build/device -allowProvisioningUpdates DEVELOPMENT_TEAM=LMHJKZ2N43 CODE_SIGN_STYLE=Automatic build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device 00008120-0014354C112B601E build/device/Build/Products/Debug-iphoneos/PencilEcho.app
```

Debug builds include the Debug menu (004 spike, 007 Qwen test) used by the owner device checks. Free provisioning expires after 7 days. Rerun both commands to renew; documents are kept.

## Native renderer dependency (011)

Xcode resolves the exact SwiftMath 1.7.3 package pinned in `application/PencilEcho.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Initial package resolution needs network access; rendering itself works offline. Bundle its font resources/licenses and `App/Resources/ThirdPartyNotices/SwiftMath-LICENSE.txt` when building. No additional entitlement, signing capability, paid service or storage migration is required. See [renderer verification](../testing/rich-text-011.md).

## Native provider configuration (013)

Anthropic and Gemini are selected in the existing AI Settings provider picker. Use a base URL (`https://api.anthropic.com/v1` or `https://generativelanguage.googleapis.com/v1beta`), not a complete message/generation endpoint. Use a bare model ID and save the appropriate provider key locally in Keychain. Each endpoint override requires its own saved key. There are no new dependencies, signing capabilities, services or migrations. Native fixtures do not establish a real-provider or physical-device run; follow [the owner acceptance steps](../api/providers.md#owner-live-acceptance) and record the two providers separately.
