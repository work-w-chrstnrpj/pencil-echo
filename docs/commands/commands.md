# Command Reference

This page documents the commands currently implemented by the AI preset template. Run commands from the template repository unless `--into` points at another project.

## Requirements

```bash
node --version
```

The CLI requires Node.js 18 or newer and has no third-party runtime dependencies.

## Show Help

```bash
node bin/create-preset.mjs --help
```

Displays supported providers, profiles, options, and examples. It does not modify files.

## Generate a Provider Preset

```bash
node bin/create-preset.mjs <provider> [options]
```

Supported providers are `cursor`, `antigravity`, `claude`, `codex`, and `opencode`.

Examples:

```bash
node bin/create-preset.mjs cursor --profile fullstack
node bin/create-preset.mjs claude --profile qa --into ../my-project
node bin/create-preset.mjs codex --profile architecture --into ../my-project --dry-run
```

This command creates or updates generated adapters and selected shared assets. Existing user-owned files are skipped unless `--force` is supplied.

## Synchronize Adapters

Synchronize every supported provider:

```bash
node bin/create-preset.mjs sync --target all
```

Synchronize one provider in another project:

```bash
node bin/create-preset.mjs sync --target cursor --profile fullstack --into ../my-project
```

Synchronization mutates generator-managed files. It preserves conflicting user-owned files by default.

## Validate Structure and Context

Validate the current repository:

```bash
node bin/create-preset.mjs validate
```

Validate another project:

```bash
node bin/create-preset.mjs validate --into ../my-project
```

Validate context for a specific task:

```bash
node bin/create-preset.mjs validate --into ../my-project --task api
node bin/create-preset.mjs validate --into ../my-project --task database
node bin/create-preset.mjs validate --into ../my-project --task deployment
node bin/create-preset.mjs validate --into ../my-project --task testing
```

General missing context produces warnings. Missing context required by the selected task produces errors and a nonzero exit code. Validation does not modify files.

## Measure Context Size

```bash
node bin/create-preset.mjs measure
node bin/create-preset.mjs measure --profile fullstack --into ../my-project
```

Reports approximate role and playbook token counts and Cursor rule overhead. Measurements use a character-based estimate and do not represent provider billing or exact model tokenization. This command does not modify files.

## Options

| Option | Applies to | Effect |
| --- | --- | --- |
| `--profile <name>` | Generate, sync, measure | Selects `fullstack`, `general`, `qa`, `architecture`, `docs`, or `all`. Generation and sync default to `fullstack`; measurement currently reports all configured profiles. |
| `--into <dir>` | All commands | Uses another directory as the generation, validation, or measurement target. Defaults to the current directory. |
| `--target <provider\|all>` | Sync | Selects one provider or every supported provider. Defaults to `all`. |
| `--task <name>` | Validate | Requires context for `api`, `database`, `deployment`, or `testing`. |
| `--dry-run` | Generate, sync | Reports planned operations without writing files. |
| `--force` | Generate, sync | Allows replacement of conflicting user-owned files. Review with `--dry-run` first. |
| `--clean` | Generate, sync | Removes stale skill directories from the selected provider adapter. Review with `--dry-run` first because custom directories can be removed. |
| `--help`, `-h` | CLI | Displays help without modifying files. |

## Output Statuses

| Status | Meaning |
| --- | --- |
| `created` | A destination file did not exist and was created. |
| `updated` | A managed file or forced destination was replaced. |
| `unchanged` | Source and destination content already matched. |
| `skipped_user_file` | A conflicting user-owned file was preserved. |
| `removed_stale` | A stale skill directory was removed by `--clean`. |

## Safe Usage Pattern

For an existing project, use this sequence:

```bash
node bin/create-preset.mjs cursor --profile fullstack --into ../my-project --dry-run
node bin/create-preset.mjs cursor --profile fullstack --into ../my-project
node bin/create-preset.mjs validate --into ../my-project
```

Inspect every `skipped_user_file` before deciding whether `--force` is appropriate.

## npm Script Shortcuts

Inside the template repository:

```bash
npm test
npm run validate
npm run measure
npm run sync
```

Pass CLI arguments through npm after `--`:

```bash
npm run create-preset -- cursor --profile general --into ../my-project
npm run validate -- --task api --into ../my-project
npm run sync -- --target cursor --profile fullstack --into ../my-project
```

## Automated Tests

```bash
npm test
```

Runs the Node.js test suite. Tests create temporary directories and remove them after execution. They do not intentionally modify project source files.

## Legacy PowerShell Commands

Generate all legacy adapters:

```powershell
pwsh -NoProfile -File scripts/sync-ai-adapters.ps1 -Target all
```

Validate legacy adapter structure:

```powershell
pwsh -NoProfile -File scripts/validate-ai-template.ps1
```

The Node.js CLI is the primary cross-platform interface. The PowerShell scripts remain compatibility tools and support additional legacy targets.

## Commands Not Provided by This Template

This repository does not define a project application runtime, build command, deployment command, database migration command, or end-to-end test command. Fill those project-specific commands in `AGENTS.md` and `.agents/tools/verification-commands.md` after choosing the application stack.

No preset command deploys to production or changes secrets.
