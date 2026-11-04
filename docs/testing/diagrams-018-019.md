# Diagram drawing and precise ink — 018/019

Date: 2026-11-05 (Asia/Manila). Fixture-tested on the iPad (A16) simulator. Owner A16/Pencil and real-provider acceptance were not run.

## What the simulator checks cover

Ticket 018 adds canvas commands version 3: `arc`, `rect`, `wave` and `zigzag` strokes, arrowheads (`none`, `end`, `start`, `both`, `mid`), dense fill ink, and up to 16 text or LaTeX labels of 40 bytes. Expanded waves, zigzags, arcs, arrowheads and fills count toward the existing 2,048-point budget. Version 1 and 2 answers still validate; version 3 fields on those answers are schema errors. Labels are ordinary AI text or LaTeX objects created in the same undo step as the ink. They do not add a document-schema field.

Ticket 019 sends a second, magnified PNG when the newest ink is less than half as long as the context image and the magnified scale (at most 3×) is higher than the context scale. The prompt gives `focusImageScale` and says that image is for reading detail. Page-coordinate ink uses `coordinates: "page"` with null width and height; every drawn point must be on the page and within 64 points of the capture. Overlay prompt rules tell the model to trace open space, use a distinct color, and keep one continuous path. The capture grid hint was not implemented. It stays optional until a real-provider run shows it helps, and it is never drawn on the document. The app does not solve mazes or snap AI ink to user strokes.

Placed AI ink is recolored to the canvas AI ink color when the answer is applied. Geometry tests that call the ink converter directly still see the stroke's own color. A placed Feynman diagram is one color; the wave, arrowheads and labels are what distinguish its parts.

## Commands

Per-command Xcode selection. Derived data was `/tmp/PencilEcho-018` so this run did not share the default build database. Destination was the booted iPad (A16), id `709D6F70-328D-4458-8F8A-B2C47A945A80`.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,id=709D6F70-328D-4458-8F8A-B2C47A945A80' -derivedDataPath /tmp/PencilEcho-018 -parallel-testing-enabled NO -only-testing:PencilEchoTests/DiagramCommandTests -only-testing:PencilEchoTests/VisualCommandTests -only-testing:PencilEchoTests/CommandValidatorTests -only-testing:PencilEchoTests/VisualAnswerTests -only-testing:PencilEchoTests/ContextCaptureTests -only-testing:PencilEchoTests/AskAIEditorTests test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,id=709D6F70-328D-4458-8F8A-B2C47A945A80' -derivedDataPath /tmp/PencilEcho-018 -parallel-testing-enabled NO -only-testing:PencilEchoTests/DiagramCommandTests -only-testing:PencilEchoTests/ProviderAdapterTests -only-testing:PencilEchoTests/NativeProviderTests test
```

## Results

The first hosted run executed the validator, diagram, visual-command, visual-answer, context-capture and editor suites. 60 of 61 tests passed. The failure was `rejectsMalformedDiagramValues`: `sweep: 1e400` is rejected as malformed JSON because the number overflows JSON parsing, not as a field limit. The test now accepts that malformed result and checks a finite sweep of 5000° as the limit error.

The rerun, after that test correction, passed **40 tests in 3 suites** (`DiagramCommandTests`, `NativeProviderTests`, `ProviderAdapterTests`). That includes the corrected limit test and the two-image request order for the OpenAI-compatible, Anthropic and Gemini adapters (context image, then focus image).

Covered by the passing tests:

- Version 2 drawings still validate. New kinds, arrows and labels are schema errors on version 2.
- Arc endpoints, wave peaks one wavelength apart, arrowhead direction at the end, start and middle, and fill coverage of a rectangle.
- The recorded Feynman answer in `tests/fixtures/providers/feynman-diagram.json` validates, places more than five strokes, and places five AI labels including `\gamma` beside the ink, in one undo step.
- The recorded maze answer in `tests/fixtures/providers/maze-path.json` converts to strokes at the expected page positions. Page ink far from the capture or off the page is rejected and changes nothing.
- A focus image is created only for a small attention region, at a scale above the context scale and at most 3×, with a matching PNG width.

No full hosted suite is claimed. No Release build was run for these tickets. No owner document, live key, or provider request was used. The Feynman prompt, the free-body prompt, and the five maze tries on a physical iPad were not run, so there is no model name and no success count to record.
