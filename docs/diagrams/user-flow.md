# User Flow

Status: PLANNED conceptual view; exact schemas/implementation pending.

```mermaid
flowchart TD
    Library[Local library] --> Create[Create Canvas or A4 notebook]
    Create --> Write[Write or add content]
    Write --> Ask[Manual ask or tap suggestion]
    Ask --> Answer[Editable result beside problem]
    Answer --> Edit[Edit or undo]
    Edit --> Reopen[Save and reopen]
    Library --> Export[Export or backup]
```

## Implemented library path (009)

The diagram above remains broader product intent. This library path is implemented and simulator-tested; physical product acceptance is separate.

```mermaid
flowchart TD
    Grid[Local manifest-backed library] --> New[New Canvas / Notebook]
    New --> Package[Save new local package]
    Package --> Editor[Native editor]
    Grid --> Check{Package readable?}
    Check -->|Yes| Editor
    Check -->|No| Explain[Can't open / newer-version explanation]
    Editor --> Done[Done: save or show unsaved-change choice]
    Done --> Refresh[Reload library and thumbnails]
    Grid --> Rename[Rename: atomically change manifest only]
    Grid --> Confirm{Confirm permanent deletion?}
    Confirm -->|Cancel| Grid
    Confirm -->|Delete| Remove[Delete package; reload grid]
```
