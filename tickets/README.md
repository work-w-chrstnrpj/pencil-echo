# Tickets

## Purpose

This folder stores tickets: short-lived work items that track bugs, feature requests, tasks, or spikes during active development.

## Expected Contents

-   Markdown files (`.md`) describing individual work items.
-   Each ticket should be self-contained: what, why, acceptance criteria, and links to related issues or source files.

## Naming Conventions

-   Use a descriptive kebab-case name: `fix-login-timeout.md`, `add-export-endpoint.md`.
-   Prefix with a number if ordering is needed: `001-fix-login-timeout.md`.
-   Avoid generic names like `todo.md` or `issue.md`.

## Lifecycle

1.  **Open** -- ticket is created, not yet started.
2.  **In Progress** -- work has begun.
3.  **Resolved** -- change is implemented and verified.
4.  **Closed** -- merged and deployed.

For larger initiatives, consider tracking work in `docs/development-plan/development-plan.md` instead.
