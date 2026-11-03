# 006 — AI canvas command schema v1 and validator

Milestone: PE-000 · Status: Resolved (2026-11-03) · Owner: Claude (spec + implementation, taken over from Codex to parallelize) · Depends on: 003

## What

A bounded, versioned JSON format for what the AI may do to a document, plus a validator that rejects anything invalid before mutation.

## Why

Gate 6. AI output is untrusted. Answers must be applied as one validated, undoable transaction, never blind overwrites of the user's work.

## Spec (`docs/api/canvas-commands-v1.md`)

Response envelope:

```json
{ "version": 1, "requestId": "uuid", "operations": [ ... ], "message": "optional chat text" }
```

Operations v1:

- `add_object`: `type` (`markdown` | `latex` | `text`), `source`, optional `placement` hint (`right_of_selection`, `below_selection`) or explicit `frame`.
- `edit_object`, `delete_object`: only on objects in the request's scope and only when the request carries an explicit replace/delete authorization flag.

Rules:

- Limits: max 20 operations, max 20 KB source per object, frames inside page bounds.
- Unknown types/fields → reject whole response (no partial apply).
- Stale check: if the target document `revision` ≠ the request's captured revision → `needsReview`, not apply.
- Duplicate `requestId` already applied → ignore.

Port the answer shape and prompt contract ideas from `inspiration/src/server/scene-contract.md` and `src/server/canvas-command-prompt.js` (provenance per ticket 003). Keep v1 smaller than upstream.

## Implementation scope

- `Codable` types + `CommandValidator` in `DocumentModel`, returning `.valid(ops)`, `.needsReview(reason)` or `.invalid(error)`.
- JSON Schema file (`shared/schemas/canvas-commands-v1.json`) to send to providers that support structured output.

## Exclusions

No placement algorithm (ticket 010), no diagrams or widgets.

## Spec notes (2026-11-03)

The spec is `docs/api/canvas-commands-v1.md` and the provider schema is `shared/schemas/canvas-commands-v1.json`. Both are written; the Swift types, validator and tests are still open for Codex. The spec changes this ticket in five places:

- **`requestId` is not in the model output.** The app generates it at capture and pairs it with the answer, so a model cannot pick or reuse one.
- **A fourth result, `.duplicate`,** is a silent no-op, so it is not reported as an error.
- **Staleness uses the captured region,** matching ticket 010. A changed revision gives `needsReview` only when the content inside the captured region changed.
- **`add_object.placement` gains `at_frame`.** Upstream puts answers in place, for example after `3+2=`.
- **The provider schema uses `anyOf` and nullable required fields** instead of optional ones, so it works with OpenAI strict mode, Anthropic tools and Gemini.

The acceptance tests are the "Test cases" table in the spec, which covers the list below and more.

## Acceptance

- [x] Unit tests: valid add; oversize source; too many ops; unknown type; edit without authorization; stale revision; duplicate request ID; malformed JSON.
- [x] The validator never mutates a document.

## Implementation evidence — 2026-11-03 (Claude)

- `shared/CanvasCommands/CanvasCommands.swift`: the types (`CanvasOperation`, `CommandRequestContext`, `DocumentValidationState`, `ValidationResult`, `CommandError`, `CommandLimits`).
- `shared/CanvasCommands/CommandValidator.swift`: a pure `CommandValidator.validate(_:context:state:)` that runs the spec's check order.
  - It parses with `JSONSerialization` and checks keys explicitly, so unknown or missing fields are rejected and every error carries a JSON pointer. `Codable` would silently drop unknown keys.
  - Booleans are not accepted as numbers.
  - It never takes a document, store or undo manager.
- `tests/PencilEchoTests/CommandValidatorTests.swift`: 29 Swift Testing cases.
  - They cover every row of the spec's test table, plus limit edges, envelope and missing fields, placement/frame mismatch, conflicting operations, and a check that `shared/schemas/canvas-commands-v1.json` names every Swift `op`, `type` and `placement` value.
  - `1e400` is rejected by `JSONSerialization` as malformed; the test accepts that or a geometry error, as the spec allows.
- Documented `test` command on `iPad (A16)` / iOS 27.0: `TEST SUCCEEDED`, 43 tests in 5 suites, including 29/29 in `CommandValidatorTests`.
- Added 3 files to `project.pbxproj` (DocumentModel › CanvasCommands group, Tests group); `plutil -lint` OK. The ticket 004 spike entries Codex had already added were kept.
- No ported upstream code, so no provenance header (the spec is a design reference only).
