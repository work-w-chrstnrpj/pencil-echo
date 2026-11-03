# Provider fixtures

Hand-authored synthetic protocol fixtures based on official Chat Completions shapes, not recordings from a real account. No keys, prompts from users or live provider bodies. stream-success.sse is a valid v1 answer split across deltas followed by stop, usage and DONE; malformed.sse is invalid SSE JSON. HTTP status fixtures cover 401/429. Tests also construct fragmented/multiline/UTF-8 and truncation cases.

generate-handwriting.swift produces the bundled synthetic handwritten-style PNG for 2x + 3 = 11 using our own strokes; no upstream asset or personal handwriting is used. Run it from the workspace root with swift.
