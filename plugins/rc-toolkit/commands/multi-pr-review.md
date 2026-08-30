---
description: Run a multi-agent PR review (Claude + Antigravity + Codex)
model: sonnet
context: none
argument-hint: [--range from..to] [--plan path] [--scope path] [--ledger path]
---

# Multi PR Review

You are a consolidator. Launch three independent review subagents in parallel, collect their results, and produce a unified report. Do NOT perform any review yourself.

## Arguments

`$ARGUMENTS` may carry:

- `--range <from>..<to>` — **delta mode**. Reviewers cover only these commits: verify the fixes in `--plan`, and look for regressions they introduced. Without it, this is a **full review** of the branch against its base.
- `--plan <path>` — the fix plan to verify (delta mode).
- `--scope <path>` — a scope file (PR intent + file list) from `review-loop`. Pass it through to validation.
- `--ledger <path>` — a review-loop ledger. Pass it through to validation.

## Reviewer Brief

Every reviewer gets this brief, verbatim — the Claude reviewer in its prompt, Codex as its instructions argument, agy as the text after `--range`. It is what keeps a reviewer from inventing findings to justify its existence.

```
Flag only issues that affect correctness, security, or the PR's stated intent.
Cite file:line for every finding. Do not report style, naming, or preference.
Report a change that is outside the PR's stated intent as scope creep.
Do not report a claim you cannot verify from the files in the workspace.
```

In delta mode, append:

```
Review ONLY the changes in <from>..<to>. For each fix in <plan>, state whether it is resolved, not resolved, or introduced a regression, with evidence. Do not review code outside these commits.
```

## Step 1: Detect Base Branch

Prefer the PR's actual base branch so stacked PRs compare correctly; fall back to `main` / `master`:

```bash
gh pr view --json baseRefName -q .baseRefName 2>/dev/null || (git rev-parse --verify --quiet origin/main >/dev/null 2>&1 && echo main || (git rev-parse --verify --quiet origin/master >/dev/null 2>&1 && echo master))
```

```bash
git branch --show-current
```

If the current branch IS the base branch, tell the user and stop.

In full mode the review target is `<base>...HEAD`. In delta mode it is `<from>..<to>`. Read the PR intent from `--scope` if given, otherwise from `gh pr view --json title,body`, so you can paste it into the brief.

## Step 2: Launch Three Review Subagents

Use the **Agent tool** to spawn all three in a **single message** so they run in parallel.

**CRITICAL RULES:**
- All three Agent calls MUST be in a single message
- Do NOT perform any review logic yourself
- Do NOT modify or summarize subagent outputs before consolidation
- Paste the brief (and the delta addendum when in delta mode) into every prompt

### Subagent 1 — Claude PR Review

The `pr-review-toolkit:review-pr` skill computes its own diff, so in delta mode the range is enforced by the brief's addendum and by validate-review's out-of-range filter, not by the skill.

```
Agent(
  description="Claude PR review",
  prompt="You are reviewing a PR. The base branch is <BASE_BRANCH>. Review target: <base>...HEAD | <from>..<to>. PR intent: <title + body>.\n\n<BRIEF>\n\nInvoke the review skill by calling: Skill(skill='pr-review-toolkit:review-pr'). Return the complete review output exactly as produced, with the reviewer name on every finding. Do not add your own analysis."
)
```

### Subagent 2 — Codex Review

Full mode:

```
Agent(
  description="Codex PR review",
  prompt="You are running an OpenAI Codex PR code review. Invoke: Skill(skill='rc-toolkit:codex-review-pr', args='<BRIEF as one line>'). Return the complete review output exactly as produced. Do not add your own analysis."
)
```

Delta mode: pass `--base <from>` so Codex diffs only the fix commits:

```
Agent(
  description="Codex delta review",
  prompt="You are running an OpenAI Codex code review of the commits <from>..<to>. Invoke: Skill(skill='rc-toolkit:codex-review-pr', args='--base <from> <BRIEF + delta addendum as one line>'). Return the complete review output exactly as produced. Do not add your own analysis."
)
```

### Subagent 3 — Antigravity Review

Full mode:

```
Agent(
  description="Antigravity PR review",
  prompt="You are running a Google Antigravity (agy) PR code review. Invoke: Skill(skill='rc-toolkit:agy-review-pr', args='<BRIEF as one line>'). Return the complete review output exactly as produced. Do not add your own analysis."
)
```

Delta mode: pass `--range <from>..<to>` so the diff file agy reads contains only the fix commits, followed by the brief:

```
Agent(
  description="Antigravity delta review",
  prompt="You are running a Google Antigravity (agy) code review of the commits <from>..<to>. Invoke: Skill(skill='rc-toolkit:agy-review-pr', args='--range <from>..<to> <BRIEF + delta addendum as one line>'). Return the complete review output exactly as produced. Do not add your own analysis."
)
```

In full mode, pass the brief the same way: `args='<BRIEF as one line>'`.

## Step 3: Consolidate Results

Once all three subagents return:

0. **Verify each reviewer actually ran.** Output beginning `AGY REVIEW FAILED:`, or empty / whitespace-only output, means the reviewer **failed — it did not find zero issues.** Reviewers can abort with a success exit code on permission denials, rate limits, or auth expiry. List each failure under **Failed** with its reason, exclude it from the reviewer count and from cross-reviewer agreement, and never let it contribute a silent "clean" vote. If *every* reviewer failed, report that the review could not be performed — do not report the PR as clean.
1. **Deduplicate** — merge issues flagged by multiple reviewers into one entry.
2. **Attribute** — every entry names the reviewer(s) that raised it. Validation uses this for its single-reviewer gate; an unattributed finding is a report bug.
3. **Classify severity:**
   - **CRITICAL**: security vulnerabilities, data loss, system-breaking bugs
   - **HIGH**: bugs and incorrect behaviour on a real code path, resource leaks, major architectural issues
   - **MEDIUM**: missing validation of real inputs, edge cases that occur in practice, performance concerns
   - **LOW**: style, hardening against cases the code cannot reach, hypotheticals, minor improvements
4. **Boost confidence** — issues flagged by 2+ reviewers carry higher weight.
5. **Discard noise** — drop style-only suggestions and clear false positives.
6. **Delta mode:** build the per-fix verification table from the reviewers' statements before listing new issues.

## Step 4: Output Report

```
## Multi PR Review Summary

**Mode:** full <base>...HEAD | delta <from>..<to>
**Reviewers:** [list which completed successfully]
**Failed:** [list which failed with error details — omit if all succeeded]
**Issues found:** [count by severity]

### Fix verification            ← delta mode only
| Fix | Status | Reviewers | Evidence |
| FIX-1 | resolved / not resolved / regression | … | … |

### CRITICAL
- [issue] — file:line — flagged by [reviewers] — [description + suggested fix]

### HIGH
...

### MEDIUM
...

### LOW
...

### Scope creep
- file:line — [change outside the PR's stated intent] — flagged by [reviewers]

### Cross-Reviewer Agreement
[Issues 2+ reviewers independently flagged]

### Recommendations
[merge-ready, needs-fixes, or needs-rework; specific action items]
```

If no issues were found across all reviewers **that actually ran**, say the changes look clean. If any reviewer failed, say so in the same breath — "clean per 2 of 3 reviewers, Antigravity failed" is honest; "clean" alone is not.

## Step 5: Validate Results

Run the validate-review command to filter false positives and give every valid issue a disposition, passing the arguments through:

```
Skill(skill="rc-toolkit:validate-review", args="<--scope … --ledger … --range … --plan …, whichever were given>")
```

The validated report replaces the consolidated report as the final output.
