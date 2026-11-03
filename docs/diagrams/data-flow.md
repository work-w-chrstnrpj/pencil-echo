# Data Flow

Status: PLANNED conceptual view; exact schemas/implementation pending.

```mermaid
flowchart TD
    Ink[PencilKit ink and content objects] --> Capture[Scoped immutable capture and revision]
    Capture --> Provider[Selected provider API]
    Provider --> Validate[Validate structured response]
    Validate --> Revision{Target still current?}
    Revision -->|Yes| Apply[One undoable transaction]
    Revision -->|No| Review[Hold for user review]
    Apply --> Save[Atomic local save]
```

## Implemented provider spike (007)

This isolated Debug path does not capture or mutate a document; a real-provider run is still pending.

```mermaid
flowchart LR
    Sample[Bundled synthetic equation + prompt/schema] --> Gate[Model/PNG/size checks]
    Gate --> Key[Keychain: exact preset + HTTPS base URL]
    Key --> HTTP[Selected endpoint: cancellable Chat Completions SSE]
    HTTP --> Bounded[Bounded SSE framing and completion checks]
    Bounded --> Preview[Debug streamed preview]
    Bounded --> Validator[Pure v1 CommandValidator]
    Validator --> Result[Show validation result; no apply/save]
```

## Implemented rich-object editing (011)

```mermaid
flowchart LR
    Source[Stored Markdown or LaTeX source] --> Sheet[Draft source sheet and live preview]
    Sheet -->|Save| Measure[Native height at object width]
    Measure --> Commit[One source/frame undo transaction and revision]
    Commit --> Disk[Atomic local document save]
    Commit --> Render[Foundation Markdown and SwiftMath]
    Render --> Canvas[Canvas, thumbnail and region capture]
    Render -->|Failure or limit| Raw[Raw source and warning]
    Zoom[Zoom ends] --> Density[Rebuild at screen scale times zoom]
    Density --> Render
```

## Selected provider dispatch (013)

```mermaid
flowchart TD
    Settings[Selected preset, endpoint and model] --> Factory[ProviderFactory]
    Factory --> OpenAI[OpenAI-compatible Chat Completions]
    Factory --> Anthropic[Anthropic Messages]
    Factory --> Gemini[Gemini streamGenerateContent]
    OpenAI --> Events[Common text, usage and completion events]
    Anthropic --> Events
    Gemini --> Events
    Events --> Validator[Existing command and stale-target validation]
    Validator --> Commit[One document transaction]
    Anthropic --> Errors[Fixed errors; no retry or provider failover]
    Gemini --> Errors
```
