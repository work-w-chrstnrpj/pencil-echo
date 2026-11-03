# Roles

## Purpose

Each file in this folder defines one portable AI engineering role. Roles own specific domains of work: architecture, product, frontend, backend, DevOps, security, QA, and documentation.

## Structure

Every role file follows this structure:

```markdown
# Agent: <Title>

## Identity

- **Name:** `<kebab-case-name>`
- **Role:** `<Display Title>`
- **Description:** `<One-line summary of ownership.>`

## Routing Trigger

When to route work to this role.

## Core Instructions

The role's operating principles and decision rules.

## Responsibilities

What the role owns.

## Non-Responsibilities

What the role does not own and should hand off.

## Reusable Skills

Standalone skills the role may invoke.

## Embedded Capability Playbooks

Domain-specific procedures, checklists, and decision rules.

## Context Routing (optional)

Where to start reading context.

## Expected Outputs

What the role produces.

## Quality Checks

How to verify the role's output.

## Handoff Rules

How to hand work to other roles.
```

## Metadata

The `Identity` section contains parseable metadata fields required by the validation script and adapter generators:

- `- **Name:**` -- kebab-case unique identifier.
- `- **Role:**` -- display title (may differ from name).
- `- **Description:**` -- short ownership summary.

## Conventions

-   Use kebab-case for file names matching the `Name` field.
-   Keep the `Identity` section at the top with the three required metadata fields.
-   Organize playbooks as `### Capability: <name>` subsections under `## Embedded Capability Playbooks`.
-   Reference skills by backtick-quoted name (e.g. `` `code-review` ``).
-   Do not embed project-specific paths (those belong in `AGENTS.md`, `docs/`, `.ai/`).

## Relationship to Adapters

Tool-specific adapters (`.claude/agents/`, `.cursor/rules/`, `.github/agents/`, `.opencode/agents/`, etc.) are **generated** from these canonical files by `node bin/create-preset.mjs sync` (or `scripts/sync-ai-adapters.ps1`). Edit the canonical role file first, then regenerate.

## Where to Start

1.  Read `AGENTS.md` and `.agents/README.md` for the overall AI structure and operating rules.
2.  Choose the smallest role that owns your task from the table below.
3.  Read that role file for full guidance.

| File | Role |
|---|---|
| `software-engineer.md` | General coding, fullstack development, refactoring, and integration |
| `system-architect.md` | Architecture and technical direction |
| `product-planning-manager.md` | Requirements and planning |
| `frontend-ui-ux-developer.md` | UI and client behavior |
| `backend-database-engineer.md` | Services, APIs, data, and integrations |
| `devops-engineer.md` | CI/CD and operations |
| `security-engineer.md` | Security and secrets |
| `sqa-engineer.md` | Testing and quality |
| `technical-documentation-specialist.md` | Documentation and changelogs |
