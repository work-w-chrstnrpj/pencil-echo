# Portable AI Agent Structure

This directory contains canonical reusable AI development assets that can move between projects.

- `roles/`: the canonical 9 engineering subagents from the reusable agent model.
- `skills/`: small reusable executable workflows shared across roles and tools.
- `overlays/`: response-style and feedback posture overlays such as Mentor and Coach.
- `workflows/`: multi-role process docs.
- `tools/`: context, command, adapter, MCP, and verification policies.

Start with `AGENTS.md`, choose the smallest role that owns the task, then use a standalone skill only when the task needs a reusable workflow such as repo Q&A, issue investigation, planning, implementation, testing, review, documentation, release checking, RCA generation, context discovery, or adapter sync.

Do not create standalone skills for every domain capability. Domain-specific procedures, checklists, and decision rules belong inside the owning role file under `Embedded Capability Playbooks` or reference playbooks.

Portable roles, skills, overlays, workflows, and tool policies should not contain project-specific source paths. Project-specific paths belong in `AGENTS.md`, `docs/`, `.ai/maps/`, and `.ai/index/`.

Generated adapters are produced from canonical files by `node bin/create-preset.mjs sync` (or `scripts/sync-ai-adapters.ps1`). Do not edit generated adapters first; update canonical `.agents/` sources, then regenerate.

Generated maps, graphs, repo maps, embeddings, and snapshots are navigation aids only. Read exact source files before edits and run relevant verification before claiming success.

## Standalone Skill Criteria

A standalone skill is allowed only if it satisfies all of these:

1. It defines a repeatable workflow, not just an area of expertise.
2. It can be reused across projects.
3. It is useful across more than one role/tool, or it is important enough to standardize.
4. It has clear inputs, workflow steps, boundaries, and output expectations.
5. It helps context efficiency rather than adding routing noise.

Do not create standalone skills for every agent capability. Put domain-specific checklists and procedures inside the owning role file.
