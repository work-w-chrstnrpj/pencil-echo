# Agent Map

Use this file to route work to the smallest useful role and skill.

## Canonical Roles

| Task | Primary Role | Supporting Roles |
| --- | --- | --- |
| General coding, fullstack features, refactoring, utilities | Software Engineer | System Architect, SQA Engineer |
| Architecture, module boundaries, and technical risk | System Architect | Security Engineer, implementation role |
| Requirements, acceptance criteria, and planning | Product & Planning Manager | System Architect, SQA Engineer |
| User interface or client behavior | Frontend UI/UX Developer | SQA Engineer, Security Engineer |
| Services, APIs, data, integrations, jobs, or workers | Backend & Database Engineer | System Architect, Security Engineer, SQA Engineer |
| Deployment, runtime config, CI/CD, and monitoring | DevOps Engineer | Security Engineer, Technical Documentation Specialist |
| Secrets, auth, authorization, unsafe inputs, and sensitive workflows | Security Engineer | System Architect, implementation role |
| Test plans, manual cases, automated tests, regressions, and bug reports | SQA Engineer | Relevant implementation role |
| Setup, API docs, operations docs, changelog, and onboarding | Technical Documentation Specialist | Relevant implementation role |

## Common Skill Routing

| Work | Skill |
| --- | --- |
| Plan a change | `plan-code-change` |
| Implement a change | `execute-code-change` |
| Implement a feature | `execute-code-change` |
| Fix a bug | `investigate-issue`, then `execute-code-change` |
| Investigate why an issue occurred | `investigate-issue` |
| Generate an RCA report | `generate-rca` |
| Review a patch | `code-review` |
| Add automated tests | `write-automated-test-cases` |
| Create manual test cases | `create-manual-test-cases` |
| Execute manual test cases | `execute-manual-test-cases` |
| Update docs | `update-docs` |
| Review security | Security Engineer role with `code-review` |
| Prepare for release | `release-check` |

## Tool Adapter Routing

Treat `.agents/roles/` and `.agents/skills/` as canonical. After changing either source, run `node bin/create-preset.mjs sync --target all` (or `pwsh scripts/sync-ai-adapters.ps1 -Target all`) to refresh generated adapters.

- Cursor rules and skills in `.cursor/`
- Antigravity direct integration in `AGENTS.md` and `.agents/`
- Claude adapters in `.claude/`
- Codex agents in `.codex/agents/`
- OpenCode agents and skills in `.opencode/`
