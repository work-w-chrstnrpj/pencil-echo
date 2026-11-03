# Pencil Echo product specification

Status: PLANNED — no implemented or accepted native features.

## Goal and audience

An open-source iPad workspace for anyone who wants to write, think and solve visually. The primary workflow is handwriting a problem, requesting AI assistance and receiving an editable response beside the problem. Initial installation is personal; others may build the public source when published.

## Documents and input

Separate freeform Canvas and multipage A4 notebook documents. Optional blank, lined, dotted and grid backgrounds. Pencil draws; touch pans/zooms and operates controls. No finger drawing. Support erasing, ink/object lasso, move/resize, text, images, equations, Markdown, undo/redo and autosave. Ink and content objects remain editable after reopen.

## AI behavior

User supplies provider keys and selects a provider (Qwen first; also OpenAI, Anthropic, OpenRouter, Google Gemini, Cerebras, Groq, Hugging Face, Mistral, NVIDIA), model and optional custom endpoint. Handwriting requests need a vision-capable model; the app says so instead of silently sending text only. Manual requests and opt-in suggestion popups precede optional automatic solving. A suggestion must not invoke a paid solving request until tapped; if generating suggestions itself requires provider usage, its consent/cost behavior must be specified before implementation.

Lasso requests include selected content plus a small margin; general requests use the viewport. Relevant conversation and referenced objects may accompany follow-ups. Whole-document context requires explicit scope choice. Explain remote processing before enabling automatic features.

Valid results appear automatically beside the problem without obscuring original writing. AI edits to existing work require an explicit replace/delete instruction. One operation equals one undo step. If target content changed during the request, show a review state before applying. Never silently apply stale mutations or auto-retry a billable failed request.

Text, formulas and diagrams are editable. Architecture, sequence and workflow diagrams support direct node/connector edits plus conversational refinement. Chat can operate within authorized document scope.

## Library and portability

Projects/folders, tags, bookmarks, typed-text search and handwriting-search capability, reusable independent cards with source navigation, trash, bounded history, backup/restore. Recognition quality must be tested; unrecognized handwriting is retained and must not be presented as fully searchable.

Import images/PDF; PDF pages become notebook backgrounds with original aspect ratio preserved within A4. Export editable documents, PDF and PNG; manual backup archives. Later SVG/Markdown exports must disclose unsupported content. Missing/deleted card sources do not destroy saved cards.

## Later capabilities

Authenticated paired LAN MCP while foregrounded, opted-in documents only. Codex, Claude Code and Cursor are candidate clients pending independent verification. Widgets/quizzes/simulations use constrained web surfaces; 3D requires a passing A16 performance prototype. Widgets have no keys or broad document access and start without network access.

## Quality and exclusions

English, portrait/landscape, supported multitasking, multiple windows, keyboard/trackpad, VoiceOver and Dynamic Type. Accessible alternatives are needed for canvas actions and AI results. Local drawing/editing/search/export function offline; remote solving needs connectivity. No required account, document lock, upstream desktop compatibility, cloud sync, hosted PenEcho models, desktop CLI execution or always-on background MCP server.

## First acceptance gate

On the owner's A16/USB-C Pencil: create a document, write a problem, request a solution, receive an editable answer beside it, undo the answer, then save/reopen with expected content preserved. Test retained results separately from undone results. Device acceptance is owner verification, not inferred from simulator/build success.
