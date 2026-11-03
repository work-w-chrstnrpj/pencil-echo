---
name: investigate-issue
description: Top-level diagnostic workflow for investigating issues and incidents using evidence, dynamically routing to the correct specialist agent, identifying symptoms and failing boundaries, evaluating hypotheses, and determining the most likely root cause only when supported. Use when asked to debug why an issue occurred or produce an investigation report before RCA writing; do not use to write formal RCAs or generate PDFs.
---

# Investigate Issue

## Purpose

Investigate why a reported issue occurred using evidence. Act as a diagnostic coordinator and investigator, not an RCA writer.

Use this model:

- Skill = reusable workflow.
- Agent = specialist role.
- Tool = executable capability.
- Coordinator = decides which agent leads or participates.

Do not hard-code this workflow to one specialist. Route by evidence. Do not assume a root cause without evidence. If the available evidence is insufficient, explicitly state that the root cause has not been determined.

## Inputs

Use any provided or discoverable evidence, including:

- Bug reports and reproduction steps.
- Application logs, stack traces, metrics, and monitoring data.
- API requests and responses.
- Database records.
- Source code, configuration files, commits, and deployment history.

## Specialist Routing

Use evidence to assign the primary investigator:

- Frontend/UI evidence: `frontend-ui-ux-developer`
- API or business logic evidence: `backend-database-engineer`
- Database, query, or schema evidence: `backend-database-engineer`
- Infrastructure, deployment, network, startup, DNS, or container evidence: `devops-engineer`
- Authentication, authorization, permission, secrets, or security evidence: `security-engineer`
- Architecture boundary, ownership, or data-flow confusion: `system-architect`
- Reproduction, acceptance, regression, or test-gap evidence: `sqa-engineer`
- Cross-cutting evidence: assign one lead investigator and list supporting specialists.

When evidence is unclear, use these defaults:

- User-facing bug: `sqa-engineer`
- Cross-service or unclear ownership: `system-architect`
- Deployment, outage, startup, DNS, container, or infrastructure issue: `devops-engineer`
- Auth or security issue: `security-engineer`

## Workflow

1. Gather objective facts first: error messages, status codes, timestamps, affected endpoints, affected users, services, versions, deployments, and relevant records.
2. Identify visible symptoms from user reports, UI behavior, logs, APIs, monitoring, or tests.
3. Identify the suspected failing boundary, such as frontend, backend, database, auth, infrastructure, deployment, integration, or cross-service flow.
4. Assign a primary investigator and supporting specialists using the routing rules.
5. Identify observations and patterns from the facts without jumping to conclusions.
6. Generate multiple plausible hypotheses, such as permission mapping, missing data, migration issues, configuration mismatch, dependency failure, or a regression.
7. Evaluate each hypothesis with supporting evidence, contradicting evidence, and missing evidence.
8. Determine the most likely cause only when evidence supports it.
9. Assign a confidence level: High, Medium, or Low.
10. Recommend fixes and the next evidence to collect.
11. Decide whether a formal RCA is needed.

## Boundaries

- `investigate-issue` = find evidence, isolate failing boundary, rank hypotheses.
- `execute-code-change` = modify files.
- `generate-rca` = write final formal RCA after evidence exists.
- Do not auto-fix.
- Do not write formal RCA.
- Do not generate PDFs.

## Rules

- Separate symptoms, facts, observations, hypotheses, evidence, and conclusions.
- Prefer code references, logs, database records, API responses, configuration, and deployment evidence.
- Do not present assumptions as facts.
- Do not fabricate missing evidence.
- It is valid to conclude: `Root cause could not be confirmed with the available evidence.`
- Do not write the formal RCA.
- Do not generate PDFs.

## Required Output

```markdown
# Investigation Report

## Summary

Brief summary of the issue.

## Symptoms

Visible symptoms reported by the user, system, logs, UI, API, or monitoring tools.

## Facts

Objective facts discovered.

## Observations

Analysis of the facts and patterns.

## Suspected Failing Boundary

The likely failing layer or boundary, such as frontend, backend, database, auth, infrastructure, deployment, integration, or cross-service flow.

## Primary Investigator

The specialist agent best suited to lead the investigation based on the evidence.

## Supporting Specialists

Other agents that should participate, if the issue crosses multiple domains.

## Hypotheses

List plausible causes. For each hypothesis, include:

- Supporting evidence
- Contradicting evidence
- Missing evidence

## Evidence

Code references, logs, database records, API responses, configuration settings, deployment history, screenshots, or other supporting information.

## Most Likely Root Cause

Provide only if the evidence supports it. If not confirmed, state:

> Root cause not yet determined.

## Confidence Level

High / Medium / Low

## Recommended Fixes

Potential remediation actions.

## Open Questions

Information still required to complete the investigation.

## RCA Needed?

Yes / No

Explain whether a formal RCA should be generated.
```
