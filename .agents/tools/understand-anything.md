# Understand Anything

## Role

Understand Anything is an optional onboarding and broad exploration tool.

## Use when

- the repository is large or unfamiliar
- a new developer or AI agent needs onboarding
- visual/domain exploration is helpful
- broad business workflow understanding is needed

## Do not use when

- simple search is enough
- target files are already known
- exact implementation truth is needed
- Graphify already gives enough relationship context

## Context rule

Understand Anything output is an exploration aid, not truth.
Exact source files and tests are truth.

## Invocation rule

Do not run Understand Anything by default.
Do not run it alongside Graphify unless there is a clear reason.

## Generated output policy

Store generated output under `.understand-anything/` or another ignored path.
Do not commit large generated analysis by default.
