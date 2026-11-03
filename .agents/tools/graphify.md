# Graphify

## Role

Graphify is an optional repository relationship/navigation map.

## Use when

- exploring unfamiliar code areas
- finding dependencies or call paths
- planning refactors
- onboarding an agent to a module
- identifying likely files before exact reads

## Do not use when

- the target files are already known
- simple search is enough
- exact implementation behavior is needed
- the generated graph may be stale and no source verification will follow

## Context rule

Graphify output is navigation only.
Exact source files and tests are truth.

## Invocation rule

Do not run Graphify for every prompt.
Run it only when relationship discovery is useful.

## Generated output policy

Ignore generated graph output by default unless the project intentionally commits a small reviewed summary.
