# Allowed Commands

## Safe Command Categories

- Package manager install only when requested or necessary.
- Lint, typecheck, tests, and build.
- Grep/search and non-destructive file inspection.
- Directory listing.
- `git status`, `git diff`, `git log`, and other non-destructive git inspection.
- Local dev server commands when needed for verification.

## Risky Commands Requiring Approval

- `rm`, `rmdir`, delete, or recursive removal.
- `git reset`, `git clean`, checkout/revert of user changes.
- Force push.
- Migration execution.
- Production deployment.
- Secret or production config changes.
- Global installs.
- Docker prune.
- Database destructive operations.

When unsure, ask before acting.
