# Tests

`PencilEchoTests/ScaffoldTests.swift` belongs to the hosted `PencilEchoTests` target in `application/PencilEcho.xcodeproj`. Its three Swift Testing placeholders cover discovery for the App, DocumentModel and Services logical groups; they contain no feature assertions.

Use the native commands in [the verification strategy](../docs/testing/test-specification.md). Root `*.test.mjs` files exercise copied AI-template tooling only and are not native app tests. Manual and physical-device evidence must remain separate from automated results.

`evidence/002/home-portrait.png` records the visually inspected scaffold launch on the iPad (A16) simulator, 2026-11-03. The matching ticket and testing document record commands and limitations.

`PencilEchoTests/InkObjectSpikeTests.swift` adds eleven Debug-only tests for ticket 004. At ticket 004 delivery, the Debug suite had fourteen tests including the scaffold placeholders. `evidence/004/` holds visually inspected simulator screenshots; [the spike report](../docs/spikes/004-ink-object-layer.md) records commands and physical checks still required. Deterministic gesture-handler tests do not emulate UIKit touch dispatch or Pencil hardware.

`ProviderAdapterTests.swift` adds 20 provider test methods using `fixtures/providers/` and production URLSession interception, with no remote calls. Keychain checks use a unique synthetic identity and clean up their own item. The latest full Debug suite passed **83 tests** across scaffold, spike, storage, validator and provider suites. `evidence/007/` records the inspected Debug screen without credentials; real-provider acceptance remains pending in ticket 007.

Ticket 009: `PencilEchoTests/LibraryTests.swift` has 19 library/metadata/thumbnail tests. `PencilEchoUITests/LibraryUITests.swift` adds two Debug-only UI journeys in the PencilEchoLibraryUI scheme. These use unique temporary libraries, never owner Documents data. Evidence and precise commands are in [library-009.md](../docs/testing/library-009.md); screenshots are under `evidence/009/`.
