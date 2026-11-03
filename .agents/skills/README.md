# Skills

Standalone skills are reusable workflows with clear triggers, steps, boundaries, and outputs. They are not a taxonomy of every engineering capability.

## Standalone Skill Criteria

A standalone skill is allowed only if it satisfies all of these:

1. It defines a repeatable workflow, not just an area of expertise.
2. It can be reused across projects.
3. It is useful across more than one role/tool, or it is important enough to standardize.
4. It has clear inputs, workflow steps, boundaries, and output expectations.
5. It helps context efficiency rather than adding routing noise.

Do not create standalone skills for every agent capability. Put domain-specific checklists and procedures inside the owning role file under `Embedded Capability Playbooks`.

| Skill | Purpose |
| --- | --- |
| `ask-repo-question` | Answer repository questions without editing files. |
| `investigate-issue` | Diagnose bugs, incidents, failed tests, or unexpected behavior using evidence. |
| `plan-code-change` | Plan a feature, bugfix, refactor, or chore without editing files. |
| `execute-code-change` | Implement a safe code change with verification and docs updates when needed. |
| `code-review` | Review changed code for correctness, architecture, security, contracts, tests, and maintainability. |
| `use-context-tools` | Use context discovery tools efficiently before editing. |
| `write-automated-test-cases` | Add or improve executable tests. |
| `create-manual-test-cases` | Create manual QA test cases from requirements or source evidence. |
| `execute-manual-test-cases` | Execute manual QA test cases and report results with evidence. |
| `update-docs` | Update docs after behavior, architecture, API, database, deployment, testing, or AI workflow changes. |
| `release-check` | Prepare code for merge or release readiness. |
| `generate-rca` | Transform completed investigation findings into formal RCA deliverables. |
| `sync-ai-adapters` | Generate tool-specific adapters from canonical `.agents/` sources. |
