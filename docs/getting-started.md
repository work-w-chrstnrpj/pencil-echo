# Getting Started With AI Presets

This guide explains how to choose, install, use, update, and troubleshoot the AI development presets in this repository.

## What This Project Installs

A preset combines four kinds of reusable guidance:

- **Roles** define who owns the work, such as Software Engineer, SQA Engineer, or System Architect.
- **Skills** define repeatable workflows, such as planning a change, implementing code, reviewing code, or creating tests.
- **Overlays** change how the answer is presented. `Mentor` teaches and explains; `Coach` critiques and challenges.
- **Workflows** connect roles and skills across an SDLC activity, such as feature delivery or release readiness.

The `.agents/` directory is the canonical source. Provider folders such as `.cursor/`, `.claude/`, `.codex/`, and `.opencode/` are generated adapters.

## Prerequisites

- Node.js 18 or newer.
- A local clone or copy of this template.
- A target project where you want to install a preset.
- One supported agentic development tool: Cursor, Antigravity/Gemini, Claude Code, Codex, or OpenCode.

The CLI currently runs directly from this repository and has no third-party npm dependencies. From the template root, confirm it is available:

```bash
node bin/create-preset.mjs --help
```

You may optionally run `npm link` from the template root to make `create-preset` and `ai-preset` available as global commands on your machine. Direct `node bin/create-preset.mjs` commands remain the documented default and do not require a global installation.

## Choose a Provider

| Provider | Generated adapter | Use it when |
| --- | --- | --- |
| `cursor` | `.cursor/rules/` and `.cursor/skills/` | The project is developed with Cursor. |
| `antigravity` | `GEMINI.md` plus canonical `.agents/` assets | The project uses Antigravity or Gemini project instructions. |
| `claude` | `.claude/agents/`, `.claude/skills/`, and `CLAUDE.md` | The project is developed with Claude Code. |
| `codex` | `.codex/agents/` plus canonical `.agents/skills/` | The project is developed with Codex. |
| `opencode` | `.opencode/agents/`, `.opencode/skills/`, and `opencode.json` | The project is developed with OpenCode. |

Install one provider first. Add more providers only when the team actually uses them.

## Choose a Profile

| Profile | Best fit |
| --- | --- |
| `general` | Small projects, general coding, refactoring, and repository questions. |
| `fullstack` | End-to-end application work involving frontend, backend, architecture, QA, and documentation. This is the default. |
| `qa` | Test planning, manual and automated testing, investigations, release checks, and RCA work. |
| `architecture` | System design, technical planning, security boundaries, and architecture review. |
| `docs` | Documentation-only work and documentation maintenance. |
| `all` | Teams that need every role and workflow. It has the largest context footprint. |

Prefer the smallest profile that covers the real work. You can regenerate with a different profile later.

## Install a Preset Into a Project

Run the command from the template repository. Use `--into` to point at the target project:

```bash
node bin/create-preset.mjs cursor --profile fullstack --into ../my-project
```

Preview the operation first when the target already contains AI configuration:

```bash
node bin/create-preset.mjs cursor --profile fullstack --into ../my-project --dry-run
```

The installation includes the provider adapter and the selected canonical roles, skills, overlays, workflows, playbooks, context maps, configuration, and documentation templates.

Existing user-owned files are skipped by default. Generated files contain an ownership marker so normal synchronization can update them later.

## Fill In Project Context

Open the target project and complete these files first:

1. `AGENTS.md`: project goal, overview, stack, repository map, and verification commands.
2. `docs/tdd/tdd.md`: architecture, constraints, responsibilities, and runtime behavior.
3. `docs/project-structure/project-structure.md`: source layout and module ownership.
4. `docs/product-specification/product-specification.md`: users, workflows, requirements, and acceptance criteria.

Complete conditional documents only when relevant:

- `docs/api/api-specification.md` for API work.
- `docs/database/data-model.md` for persistent data.
- `docs/testing/test-specification.md` for the testing strategy.
- `docs/deployment/deployment.md` for deployment and operations.

Use `Status: NOT_APPLICABLE` when a conditional document does not apply.

Validate the context from the template repository:

```bash
node bin/create-preset.mjs validate --into ../my-project
```

Warnings identify incomplete general context. A task-specific validation becomes blocking only when that task needs an unfinished document:

```bash
node bin/create-preset.mjs validate --into ../my-project --task api
```

Supported task checks are `api`, `database`, `deployment`, and `testing`.

## Use Roles, Skills, and Overlays

The most portable way to activate guidance is to name it in the prompt. Providers that support automatic selection may choose the matching agent or skill from its description; naming it removes ambiguity.

Implement a feature:

```text
Use the Software Engineer role and execute-code-change skill. Implement account settings, add appropriate tests, run verification, and update affected documentation.
```

Plan without editing:

```text
Use the System Architect role and plan-code-change skill. Plan how to split the billing module without editing files.
```

Run QA work:

```text
Use the SQA Engineer role and create-manual-test-cases skill. Create regression cases for password reset.
```

Add an explanation style:

```text
Software Engineer + Mentor ELI12: Explain how authentication state moves through this application.
```

Request critical feedback:

```text
System Architect + Coach: Challenge this event-driven architecture proposal and identify its largest operational risks.
```

Provider interfaces change over time. If your tool exposes an agent, rule, or skill picker, you can select the generated item there. Otherwise, use the explicit prompt form above.

## First End-to-End Example

From the template repository:

```bash
node bin/create-preset.mjs cursor --profile general --into ../sample-app --dry-run
node bin/create-preset.mjs cursor --profile general --into ../sample-app
node bin/create-preset.mjs validate --into ../sample-app
```

Then open `../sample-app` in Cursor, fill the core context documents, and start with:

```text
Use the Software Engineer role and ask-repo-question skill. Read AGENTS.md and the relevant project documentation, then explain the current application structure and the best place to add a user profile feature. Do not edit files.
```

After reviewing that answer:

```text
Use the Software Engineer role and execute-code-change skill. Implement the agreed user profile feature, add focused tests, run the documented verification commands, and update affected docs.
```

## Update and Synchronize Presets

Edit canonical files in `.agents/`, then regenerate adapters:

```bash
node bin/create-preset.mjs sync --target all
```

To update another project from the template repository:

```bash
node bin/create-preset.mjs sync --target cursor --profile fullstack --into ../my-project
```

Normal sync updates generator-managed files and preserves user-owned files. Review output statuses:

- `created`: a new file was written.
- `updated`: a generator-managed file was refreshed.
- `unchanged`: the destination already matched.
- `skipped_user_file`: the destination differed and was treated as user-owned.
- `removed_stale`: `--clean` removed a skill directory outside the selected profile.

Use `--force` only when you intentionally want generated content to replace a conflicting user-owned file. Use `--clean` only after a dry run and review because it removes stale skill directories from the selected provider adapter.

## Troubleshooting

### Unknown provider or profile

Run the help command and use one of the listed names:

```bash
node bin/create-preset.mjs --help
```

### A file was skipped

`skipped_user_file` means the generator protected a file it did not own. Compare the existing file with the generated source. Keep or merge the customization, or rerun with `--force` only when replacement is intended.

### Configuration JSON is invalid

The generator refuses to replace invalid JSON. Fix the syntax in the named configuration file, confirm it parses, and rerun the command. The original file is left unchanged.

### Validation reports warnings

Warnings usually mean onboarding placeholders remain. Fill the named file or mark an irrelevant conditional document `Status: NOT_APPLICABLE`.

### Task validation is blocked

Complete the document named in the error. For example, database work requires a completed `docs/database/data-model.md`.

### A provider does not discover a role automatically

Name the role and skill explicitly in the prompt. Confirm the corresponding generated adapter exists, then restart or reload the provider if it only reads project configuration at startup.

### Generated adapters are out of date

Update canonical `.agents/` files and run `sync`. Do not make the same manual edit independently in every provider folder.

For the exact CLI syntax and mutation behavior, see [Command Reference](commands/commands.md).
