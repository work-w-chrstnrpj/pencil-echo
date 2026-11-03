# MCP Policy

MCP tools and connectors may be used when they directly support the task.

## Allowed Use Cases

- Reading connected docs or design context requested by the user.
- Creating or updating user-requested external artifacts.
- Inspecting GitHub PRs, checks, or issues when relevant.
- Using approved local tools for search, verification, or rendering.

## Disallowed Risky Behavior

- Sending secrets, tokens, private env files, or credentials to external tools.
- Making production changes without approval.
- Running destructive filesystem, database, or git operations without approval.
- Installing global tools without approval.
- Uploading unnecessary repo snapshots.

## Filesystem, Network, And Secrets

Prefer local exact file reads. Treat network calls and external connectors as higher risk. Redact secrets in logs, summaries, and prompts.

## Approval Requirements

Ask before destructive operations, production deploys, force pushes, migration execution, database destructive operations, secret/config changes, or global installs.
