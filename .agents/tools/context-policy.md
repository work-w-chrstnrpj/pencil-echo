# Context Policy

## Source of Truth

- Exact source files, tests, contracts, and canonical docs are truth.
- Maps, indexes, graphs, embeddings, repo maps, and snapshots are navigation aids only.

## Default Behavior

- Use the smallest context path that can answer the question or support the change.
- Do not load all role or skill files by default.
- Prefer lazy loading and targeted reads.
- Read exact files before edits or factual claims.

## Discovery Tools

Use `rg`, file search, Graphify, Aider repo maps, Understand Anything, or Repomix only as navigation aids. Escalate to heavier tools when smaller paths are insufficient.

## Boundaries

- Do not treat generated summaries as implementation truth.
- Do not edit from generated context alone.
- Do not force large canonical trees into every tool session by default.
