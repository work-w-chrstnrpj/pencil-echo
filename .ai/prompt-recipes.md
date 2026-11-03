# Prompt Recipes

Use these prompts as starting points and adapt them to the current task.

## Implement A Feature

```text
Use AGENTS.md and the execute-code-change skill. Confirm the relevant product and technical wiki pages, identify exact files, implement the smallest safe change, add or update tests, run relevant verification, and summarize the result.
```

## Fix A Bug

```text
Use AGENTS.md and the investigate-issue skill first. Capture expected and actual behavior, reproduce or inspect evidence, identify the smallest source-confirmed fix, then use execute-code-change to add the fix, regression coverage, and relevant verification.
```

## Add Automated Tests

```text
Use AGENTS.md and the write-automated-test-cases skill. Inspect existing test patterns, choose the smallest useful test mode, add focused coverage, run the relevant test command, and report coverage gaps.
```

## Create Manual Test Cases

```text
Use AGENTS.md and the create-manual-test-cases skill. Read the source requirement, template, and previous sample if available. Write manual test cases in the requested mode and mark assumptions or open questions.
```

## Execute Manual Test Cases

```text
Use AGENTS.md and the execute-manual-test-cases skill. Read the named test case file and setup context, execute each case step by step, then report pass, fail, blocked, or not-run results with evidence.
```
