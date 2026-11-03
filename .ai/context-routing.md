# Context Routing

Use this guide before reading broad documentation pages or source folders.

## Default Flow

1. Read `AGENTS.md`.
2. Identify the task type and lead role from `.ai/maps/agent-map.md`.
3. Pick the smallest relevant map from `.ai/maps/`.
4. Inspect generated index files only if file discovery is still unclear.
5. Use search or approved context tools for exact symbol, route, dependency, and document discovery.
6. Read exact source files, tests, contracts, docs pages, or configs.
7. Edit narrowly, then verify.

## Task Routing

| Task Type | Read First | Then Inspect |
| --- | --- | --- |
| Application behavior | `.ai/maps/application-map.md` | Entry points, feature modules, state, tests |
| Service or API behavior | `.ai/maps/service-map.md` | Handlers, services, contracts, tests |
| Data model or persistence | `.ai/maps/data-map.md` | Schemas, repositories, migrations, data docs pages |
| API contract | `.ai/maps/api-map.md` | Contracts, clients, handlers, contract tests |
| Tests or failing checks | `.ai/maps/testing-map.md` | Exact failing test, subject file, setup |
| Deployment or runtime config | `.ai/maps/deployment-map.md` | Deployment docs pages, config, environment examples |

## Hard Rule

Maps, generated indexes, graphs, summaries, and embeddings are navigation aids. They are not implementation truth. Always read exact source files before edits.
