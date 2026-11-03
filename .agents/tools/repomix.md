# Repomix

## Role

Repomix is an optional portable context snapshot exporter.

## Use when

- sending controlled repo context to another AI tool
- creating an offline review artifact
- preparing a compact handoff snapshot
- sharing selected project files without giving direct repo access

## Do not use when

- working on a small known-file change
- targeted search and exact file reads are enough
- the snapshot would include secrets, dependencies, build outputs, or generated junk
- the snapshot is larger than the useful context needed

## Context rule

Repomix output is a snapshot, not truth.
It may be stale immediately after source changes.

## Invocation rule

Do not use Repomix as default coding context.
Use it only for controlled export/handoff.
