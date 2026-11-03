# AI Structure Guidelines

Complete guide for using the AI project structure template: canonical assets, tool adapters, roles, skills, overlays, workflows, and day-to-day usage.

## Purpose

This template gives any software project a **single canonical AI layer** (`.agents/`) that multiple coding tools can consume without hand-maintaining separate copies per tool.

Design goals:

- **One source of truth** for roles, reusable workflows, overlays, and process docs.
- **Quality over quantity** — few agents, few standalone skills, rich role playbooks.
- **Project-agnostic** — portable guidance in `.agents/`; project-specific paths in `AGENTS.md`, `docs/`, and `.ai/`.
- **Tool-ready** — generated adapters for Claude, Cursor, Copilot, OpenCode, Windsurf, Aider, and others.

Read `AGENTS.md` first for project-specific rules. Use this page for how the AI structure works and how to operate it.

---

## Architecture: Canonical vs Generated

```text
Canonical (edit these):
  AGENTS.md
  .agents/roles/
  .agents/skills/
  .agents/overlays/
  .agents/workflows/
  .agents/tools/

Generated (do not hand-edit first):
  CLAUDE.md, GEMINI.md
  .claude/, .codex/, .cursor/, .github/, .opencode/
  .clinerules/, .kilo/, .windsurf/
  CONVENTIONS.md, opencode.json (from sync script)
```

**Rule:** Update canonical files under `.agents/` and `AGENTS.md`, then run:

```powershell
pwsh scripts/sync-ai-adapters.ps1 -Target all
```

`scripts/generate-ai-adapters.ps1` is a compatibility wrapper that runs `-Target all`.

Validate after changes:

```powershell
pwsh scripts/validate-ai-template.ps1
```

### Linux and macOS

The sync and validation scripts use **PowerShell 7+** (PowerShell Core). That runtime is cross-platform — `.ps1` here means “run with `pwsh`,” not “Windows terminal only.”

**Install `pwsh` once:**

| OS | Example install |
| --- | --- |
| macOS | `brew install powershell` |
| Linux | [Install PowerShell on Linux](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux) (apt, yum, etc.) |

Verify:

```bash
pwsh --version
```

Run the same commands from bash or zsh:

```bash
pwsh scripts/sync-ai-adapters.ps1 -Target all
pwsh scripts/validate-ai-template.ps1
```

On Linux and macOS, `-ExecutionPolicy Bypass` is optional (it mainly matters on Windows):

```bash
pwsh -NoProfile -File scripts/sync-ai-adapters.ps1 -Target codex
```

`generate-ai-adapters.ps1` and `validate-ai-template.ps1` include a `#!/usr/bin/env pwsh` shebang, so you can also run:

```bash
chmod +x scripts/validate-ai-template.ps1
./scripts/validate-ai-template.ps1
```

`sync-ai-adapters.ps1` has no shebang — call it with `pwsh` explicitly.

Use **`pwsh`**, not **`powershell`**. The `powershell` command is Windows PowerShell 5.1 and is usually unavailable on Linux and macOS. On Windows, either `pwsh` or `powershell` works; prefer `pwsh` for consistency across the team.

---

## Getting Started With a New Project

### 1. Fill project intent first

| File | Purpose |
| --- | --- |
| `docs/tdd/tdd.md` | Technical design and implementation intent |
| `docs/product-specification/product-specification.md` | Product goals, workflows, acceptance criteria |
| `docs/project-structure/project-structure.md` | Source layout and ownership boundaries |
| `AGENTS.md` | Project goal, stack, repo map, verification commands |

### 2. Adapt code folders

Use `application/`, `service/`, `shared/`, and `tests/` for your real architecture. Remove or rename placeholders that do not apply.

### 3. Add project-specific AI routing (optional)

When the repo grows, add:

- `.ai/context-routing.md` — smallest context path per task type
- `.ai/maps/` — compact discovery maps
- `.ai/index/` — generated indexes (navigation only)

### 4. Sync tool adapters

Sync only the tools your team uses:

```powershell
pwsh scripts/sync-ai-adapters.ps1 -Target codex
pwsh scripts/sync-ai-adapters.ps1 -Target claude
pwsh scripts/sync-ai-adapters.ps1 -Target cursor
pwsh scripts/sync-ai-adapters.ps1 -Target copilot
pwsh scripts/sync-ai-adapters.ps1 -Target opencode
pwsh scripts/sync-ai-adapters.ps1 -Target windsurf
pwsh scripts/sync-ai-adapters.ps1 -Target gemini
pwsh scripts/sync-ai-adapters.ps1 -Target aider
pwsh scripts/sync-ai-adapters.ps1 -Target cline
pwsh scripts/sync-ai-adapters.ps1 -Target kilo
pwsh scripts/sync-ai-adapters.ps1 -Target openhands
pwsh scripts/sync-ai-adapters.ps1 -Target antigravity
```

**Lighter adapters** (`aider`, `cline`, `kilo`, `openhands`, `antigravity`) generate project-instruction or config files only — not full agent/skill trees. **Codex, Gemini, and Antigravity** read standalone skills from `.agents/skills/` directly — no per-tool skill copies are generated. You still run sync for Codex when role agents change so `.codex/agents/*.toml` stays current. Project instructions for Codex come from `AGENTS.md`, not a separate root file like `CLAUDE.md` or `GEMINI.md`.

Or sync everything:

```powershell
pwsh scripts/sync-ai-adapters.ps1 -Target all
```

### 5. Point your AI tool at the repo

Each tool reads project instructions differently. Common entry points:

| Tool | Start here |
| --- | --- |
| Claude Code | `CLAUDE.md`, `.claude/agents/`, `.claude/skills/` |
| Google Gemini | `GEMINI.md`, `AGENTS.md`, `.agents/` |
| Cursor | `.cursor/rules/`, `.cursor/skills/` |
| GitHub Copilot | `.github/copilot-instructions.md`, `.github/agents/` |
| OpenCode | `opencode.json`, `.opencode/agents/`, `.opencode/skills/` |
| Codex | `AGENTS.md`, `.codex/agents/`, `.agents/skills/` |
| Aider | `AGENTS.md`, `CONVENTIONS.md`, `.aider.conf.yml` |
| Cline | `.clinerules/project.md` |
| Kilo Code | `kilo.jsonc`, `.kilo/rules/` |
| Windsurf | `.windsurf/rules/`, `.windsurf/workflows/`, `.windsurf/skills/` |
| Antigravity | `AGENTS.md`, `.agents/skills/` directly |
| OpenHands | `AGENTS.md`, `.openhands/README.md` |

---

## The Eight Core Role Agents

Roles own **domain work**. Choose the smallest role that owns the task.

| Role | Use when |
| --- | --- |
| **System Architect** | Architecture, module boundaries, dataflow, technical risk, cross-module design |
| **Product & Planning Manager** | Requirements, acceptance criteria, task breakdown, sequencing, milestone tracking |
| **Frontend UI/UX Developer** | UI, components, client state, accessibility, frontend tests |
| **Backend & Database Engineer** | APIs, services, persistence, integrations, jobs, queues, data ingestion |
| **DevOps Engineer** | CI/CD, deployment, environments, monitoring, releases, operations |
| **Security Engineer** | Auth, secrets, dependency risk, threat modeling, sensitive flows |
| **SQA Engineer** | Test plans, manual/automated tests, regression, bug reporting |
| **Technical Documentation Specialist** | README, API docs, onboarding, operations, changelogs, RCA formatting |

Canonical prompts: `.agents/roles/<role-name>.md`

Each role file contains:

- **Reusable Skills** — which standalone workflow skills to invoke and when
- **Embedded Capability Playbooks** — domain procedures (API design, CI/CD, test planning, etc.) that are **not** separate skill folders

Do not add a ninth core agent. Do not merge Mentor and Coach into a `teacher` agent.

---

## Overlays: Mentor and Coach

Overlays change **response style**, not work ownership.

| Overlay | Use when |
| --- | --- |
| **Mentor** | Explanation, teaching, ELI5/ELI12, guided understanding |
| **Coach** | Critique, tradeoff review, direct feedback, decision quality |

Examples:

```text
Mentor ELI12: Explain how adapter generation works.
Coach: Critique this implementation plan.
Backend & Database Engineer + Mentor: Explain this API design.
System Architect + Coach: Challenge this architecture proposal.
```

Canonical files: `.agents/overlays/mentor.md`, `.agents/overlays/coach.md`

Combine an overlay with a role when you need both domain ownership and a different explanation or feedback posture.

---

## Standalone Skills (Reusable Workflows)

Skills are **executable workflows** shared across roles and tools — not a catalog of every engineering capability.

Curated skill set (13):

| Skill | Purpose |
| --- | --- |
| `ask-repo-question` | Answer repo questions without editing files |
| `investigate-issue` | Diagnose bugs/incidents with evidence (does not auto-fix or write RCA) |
| `plan-code-change` | Plan feature, bugfix, refactor, or chore without editing |
| `execute-code-change` | Implement a safe change with verification |
| `code-review` | Review changed code for correctness, security, tests, maintainability |
| `use-context-tools` | Efficient context discovery before editing |
| `write-automated-test-cases` | Add executable automated tests |
| `create-manual-test-cases` | Create manual QA test case documents |
| `execute-manual-test-cases` | Execute manual cases and report evidence |
| `update-docs` | Update docs after behavior or architecture changes |
| `release-check` | Prepare for merge or release readiness |
| `generate-rca` | Format completed investigation into formal RCA deliverables |
| `sync-ai-adapters` | Regenerate tool adapters from canonical `.agents/` sources |

Canonical location: `.agents/skills/<skill-name>/SKILL.md`

### When to create a new standalone skill

Create one only if **all** are true:

1. It is a repeatable workflow, not just an area of expertise.
2. It can be reused across projects.
3. It is useful across more than one role/tool, or is important enough to standardize.
4. It has clear inputs, steps, boundaries, and outputs.
5. It improves context efficiency rather than adding routing noise.

Otherwise, add guidance to the owning role under **Embedded Capability Playbooks**.

### When to update an existing skill

Update a skill when:

- Workflow steps, boundaries, or outputs change for all tools.
- A new trigger pattern applies repo-wide (not one role only).

After skill changes, run `scripts/sync-ai-adapters.ps1 -Target all`.

---

## Multi-Role Workflows

Workflows describe how roles and skills combine for common delivery paths.

| Workflow | Flow |
| --- | --- |
| `feature-delivery` | Product intent → plan → execute → tests → docs → release-check |
| `bugfix-delivery` | investigate-issue → plan (if needed) → execute → regression tests → release-check |
| `refactor-delivery` | ask/plan → execute → behavior-preserving tests → code-review → release-check |
| `chore-delivery` | plan (if risky) → execute → verification → doc/config notes |
| `release-readiness` | release-check → verify tests/build/docs/env → summarize blockers |
| `investigation-to-rca` | investigate-issue → evidence review → generate-rca when requested |

Canonical location: `.agents/workflows/*.md`

---

## How to Run a Task (Decision Guide)

```text
1. Read AGENTS.md and relevant docs pages.
2. Pick the owning role (smallest fit).
3. Pick a standalone skill only if the task matches a reusable workflow.
4. Add Mentor or Coach overlay if explanation style or critique is needed.
5. Follow the role's Embedded Capability Playbooks for domain steps.
6. Use a workflow doc when the task spans multiple roles.
7. Run verification; update docs when behavior changes.
```

### Quick examples

| User request | Role | Skill / overlay |
| --- | --- | --- |
| "Where is auth handled?" | Any | `ask-repo-question` |
| "Plan this feature" | Owning engineer + Product | `plan-code-change` (feature mode) |
| "Fix this bug" | Owning engineer | `investigate-issue` then `execute-code-change` |
| "Review my PR" | Matching specialist | `code-review` |
| "Explain this like I'm 12" | Any + Mentor | Mentor overlay |
| "Tell me what's wrong with this plan" | Any + Coach | Coach overlay |
| "Prepare for release" | Owning engineer | `release-check` |
| "We changed roles, regen adapters" | Any | `sync-ai-adapters` |

---

## Tool Adapter Reference

Generated adapters mirror canonical `.agents/` content. Edit canonical sources first.

| Tool | Agent / rules adapter | Skills adapter | Project instructions |
| --- | --- | --- | --- |
| Claude Code | `.claude/agents/*.md` | `.claude/skills/<skill>/SKILL.md` | `CLAUDE.md` |
| Google Gemini | — | `.agents/skills/` (canonical) | `GEMINI.md` |
| Cursor | `.cursor/rules/*.mdc` | `.cursor/skills/<skill>/SKILL.md` | — |
| GitHub Copilot | `.github/agents/*.agent.md` | `.github/skills/<skill>/SKILL.md` | `.github/copilot-instructions.md` |
| OpenCode | `.opencode/agents/*.md` | `.opencode/skills/<skill>/SKILL.md` | `opencode.json` |
| Codex | `.codex/agents/*.toml` | `.agents/skills/` (canonical) | `AGENTS.md` |
| Aider | — | — | `AGENTS.md`, `CONVENTIONS.md` |
| Cline | — | — | `.clinerules/project.md` |
| Kilo Code | — | — | `kilo.jsonc`, `.kilo/rules/` |
| Windsurf | `.windsurf/rules/*.md` | `.windsurf/skills/<skill>/SKILL.md` | `.windsurf/workflows/*.md` |
| Antigravity | — | `.agents/skills/` (canonical) | `AGENTS.md` |
| OpenHands | — | — | `AGENTS.md`, `.openhands/README.md` |

Regenerate:

```powershell
pwsh scripts/sync-ai-adapters.ps1 -Target <tool>
pwsh scripts/sync-ai-adapters.ps1 -Target all
```

---

## Context and Verification Policies

Tool policies live in `.agents/tools/`:

| Policy | Purpose |
| --- | --- |
| `context-policy.md` | Exact files are truth; maps/indexes are navigation only |
| `verification-policy.md` | Never claim verification passed unless it ran |
| `adapter-generation-policy.md` | Canonical vs generated adapter rules |

Context routing rules for a specific project belong in `.ai/context-routing.md` when adopted.

---

## Maintaining the Structure

### Adding domain capability guidance

1. Add or update a playbook inside the **owning role** under `Embedded Capability Playbooks`.
2. Do **not** create a new standalone skill folder unless it meets all skill criteria above.
3. Run adapter sync if role files changed.

### Changing a role

1. Edit `.agents/roles/<role>.md`.
2. Run `pwsh scripts/sync-ai-adapters.ps1 -Target all`.
3. Run `pwsh scripts/validate-ai-template.ps1`.

### Changing project-specific paths or commands

1. Edit `AGENTS.md` (repo map, verification commands, project goal).
2. Edit `docs/` pages when product or architecture docs change.
3. Do **not** put project-specific paths into portable `.agents/roles/` files.

### Documentation update rules

- Keep `docs/tdd/tdd.md` as technical intent source.
- Update API, testing, deployment, and structure docs when behavior changes.
- Keep this guidelines page aligned when the canonical AI model changes.

---

## Verification Expectations

Replace placeholders in `AGENTS.md` with real project commands:

- Lint / typecheck / test / build / e2e

For changes to the AI template structure itself:

```powershell
node bin/create-preset.mjs validate
node bin/create-preset.mjs sync --target all
npm test
```

Never claim verification passed unless commands actually ran.

---

## Common Mistakes

| Mistake | Correct approach |
| --- | --- |
| Editing `.cursor/rules/` before `.agents/roles/` | Edit canonical role, then sync |
| Creating `api-design` as a standalone skill | Add playbook to Backend role |
| Giant `Allowed Skills` lists on roles | Use `Reusable Skills` + embedded playbooks |
| Loading every role/skill file for every task | Pick smallest role; lazy-load skills |
| Treating generated maps as implementation truth | Read exact source files before edits |
| Skipping adapter sync after canonical changes | Run `create-preset sync` |
| Mentor/Coach owning implementation | Combine overlay + role for owned work |

---

## Related Files

| File | Purpose |
| --- | --- |
| `README.md` | Template overview and quick start |
| `AGENTS.md` | Project-specific agent operating rules |
| `.agents/README.md` | Canonical AI asset overview |
| `.agents/skills/README.md` | Curated skill list and criteria |
| `scripts/README.md` | Sync and validation scripts |
| `docs/guidelines/ai-structure-guidelines.md` | This document |
