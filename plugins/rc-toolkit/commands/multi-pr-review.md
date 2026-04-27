---
description: Run a multi-agent PR review (Claude + Gemini + Codex)
model: sonnet
context: none
---

# Multi PR Review

You are a consolidator. Launch three independent review subagents in parallel, collect their results, and produce a unified report. Do NOT perform any review yourself.

## Step 1: Detect Base Branch

Run these to determine the base branch and current branch:

```bash
git rev-parse --verify --quiet origin/main >/dev/null 2>&1 && echo main || (git rev-parse --verify --quiet origin/master >/dev/null 2>&1 && echo master)
```

```bash
git branch --show-current
```

If the current branch IS the base branch, tell the user and stop.

Store the detected base branch name — you will pass it to each subagent.

## Step 2: Launch Three Review Subagents

Use the **Agent tool** to spawn all three subagents in a **single message** so they run in parallel. Each subagent performs one independent review and returns its findings to you.

**CRITICAL RULES:**
- All three Agent calls MUST be in a single message (parallel execution)
- Do NOT perform any review logic yourself — you are only an orchestrator
- Do NOT modify or summarize subagent outputs before consolidation

### Subagent 1 — Claude PR Review

```
Agent(
  description="Claude PR review",
  prompt="You are reviewing a PR. The base branch is <BASE_BRANCH>. Invoke the review skill by calling: Skill(skill='pr-review-toolkit:review-pr'). Return the complete review output exactly as produced. Do not add your own analysis."
)
```

### Subagent 2 — Codex Review

```
Agent(
  description="Codex PR review",
  prompt="You are running an OpenAI Codex PR code review. Invoke the review by calling: Skill(skill='rc-toolkit:codex-review-pr'). Return the complete review output exactly as produced. Do not add your own analysis."
)
```

### Subagent 3 — Gemini Review

```
Agent(
  description="Gemini PR review",
  prompt="You are running a Google Gemini PR code review. Invoke the review by calling: Skill(skill='rc-toolkit:gemini-review-pr'). Return the complete review output exactly as produced. Do not add your own analysis."
)
```

## Step 3: Consolidate Results

Once all three subagents return:

1. **Deduplicate** — merge issues flagged by multiple reviewers into a single entry, noting which reviewers agreed
2. **Classify severity:**
   - **CRITICAL**: Security vulnerabilities, data loss, system-breaking bugs
   - **HIGH**: Bugs, incorrect behavior, resource leaks, major architectural issues
   - **MEDIUM**: Missing validation, edge cases, performance concerns
   - **LOW**: Minor improvements, style suggestions
3. **Boost confidence** — issues flagged by 2+ reviewers carry higher weight
4. **Discard noise** — drop style-only suggestions and clear false positives

## Step 4: Output Report

```
## Multi PR Review Summary

**Reviewers:** [list which completed successfully]
**Failed:** [list which failed with error details — omit section if all succeeded]
**Issues found:** [count by severity]

### CRITICAL
- [issue] — file:line — flagged by [reviewers] — [description + suggested fix]

### HIGH
...

### MEDIUM
...

### LOW
...

### Cross-Reviewer Agreement
[Issues where 2+ reviewers independently flagged the same problem]

### Recommendations
[Overall assessment: merge-ready, needs-fixes, or needs-rework]
[Specific action items if fixes needed]
```

If no issues found across all reviewers, state the changes look clean and are ready to merge.

## Step 5: Validate Results

After outputting the consolidated report, run the validate-review command to filter out false positives:

```
Skill(skill="rc-toolkit:validate-review")
```

This performs a second pass over all flagged issues, reading the actual source code to confirm each one is genuine. The validated report replaces the initial consolidated report as the final output.
