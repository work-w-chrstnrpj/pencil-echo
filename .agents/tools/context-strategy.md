# Context Strategy

Tools are escalation layers, not automatic defaults.
Exact source files and tests are always the source of truth.
Normal tasks should use routing docs, targeted search, and exact file reads first.
Invoke Graphify, Repomix, Understand Anything, Aider, or Caveman only when the task specifically needs that capability.

## Decision table

| Task situation | Default action | Tool escalation |
|---|---|---|
| Small known-file edit | Read exact file(s), edit, test | No tool |
| Unknown dependency/call path | Search first, then use relationship map if needed | Graphify |
| Coding inside terminal AI workflow | Use exact files and repo map | Aider |
| Need to send repo context to another AI/tool | Export small controlled snapshot | Repomix |
| Large unfamiliar repo / onboarding | Use broad exploration aid | Understand Anything |
| User asks for terse output / low-risk status | Use concise style | Caveman |

## Workflow

1. Read core project guidance (AGENTS.md, relevant wiki pages).
2. Use context routing / maps / indexes if available.
3. Use targeted search (rg) or exact file lookup.
4. Invoke a tool only if the task needs that tool.
5. Read exact source files before editing.
6. Verify with tests or relevant checks.

## Source of truth rule

Generated graphs, repo maps, snapshots, summaries, and dashboards are navigation aids only.
Exact source files and tests are the source of truth.

Do not run Graphify, Repomix, Understand Anything, or Caveman for every prompt.
Do not use Repomix as default coding context.
Do not edit code based only on generated context.
