---
description: Run a multi-agent PR review (Claude + Gemini + Codex)
model: sonnet
context: none
---

# Multi PR Review

Run three independent code reviews in parallel and consolidate findings into a unified report.

## Step 1: Detect Base Branch

```bash
git rev-parse --verify --quiet origin/main >/dev/null 2>&1 && echo main || (git rev-parse --verify --quiet origin/master >/dev/null 2>&1 && echo master)
```

If the current branch IS the base branch, tell the user and stop.

## Step 2: Launch Parallel Reviews

Invoke all three reviews in a SINGLE message by calling the Skill tool three times in parallel:

1. `Skill(skill="pr-review-toolkit:review-pr")`
2. `Skill(skill="rc-toolkit:codex-review-pr")`
3. `Skill(skill="rc-toolkit:gemini-review-pr")`

**CRITICAL RULES:**
- Do NOT write your own review logic or analysis — each skill handles the review autonomously
- Do NOT set any args unless the user specified review aspects
- Call all three Skill invocations in a single parallel tool call

Each skill runs its own review process (including spawning its own subagents as needed) and returns results. Your job is only to invoke them and consolidate the output.

If any reviewer fails (tool not installed, auth error, skill unavailable), note it in the report and continue with the others.

## Step 3: Consolidate Findings

Once all reviews complete:

1. **Deduplicate** — Merge issues flagged by multiple reviewers into a single entry, noting which reviewers agreed
2. **Classify severity:**
   - **CRITICAL**: Security vulnerabilities, data loss, system-breaking bugs
   - **HIGH**: Bugs causing incorrect behavior, resource leaks, major architectural issues
   - **MEDIUM**: Missing validation, edge cases, performance concerns
   - **LOW**: Minor improvements, style suggestions
3. **Boost confidence** — Issues flagged by 2+ reviewers independently carry higher weight
4. **Discard noise** — Drop style-only suggestions and clear false positives

## Step 4: Output Unified Report

```
## Multi PR Review Summary

**Reviewers:** [list which reviewers completed successfully]
**Files reviewed:** [count]
**Issues found:** [count by severity]

### CRITICAL
- [issue] — file:line — flagged by [reviewers] — [description + suggested fix]

### HIGH
...

### MEDIUM
...

### LOW
...

### Reviewer Agreement
[Issues where 2+ reviewers independently flagged the same problem]

### Recommendations
[Overall assessment: merge-ready, needs-fixes, or needs-rework]
[Specific action items if fixes needed]
```

If no issues are found across all reviewers, state the changes look clean and are ready to merge.
