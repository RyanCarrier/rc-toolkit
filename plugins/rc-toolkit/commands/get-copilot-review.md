---
description: Fetch the most recent GitHub Copilot review on the current PR and validate its findings
model: sonnet
allowed-tools: Skill, Bash(gh pr:*), Bash(gh api:*), Bash(git rev-parse:*), Bash(git diff:*), Bash(git status:*), Bash(git log:*), Read
---

# Get Copilot Review

Fetch the **most recent** GitHub Copilot review on the current PR, normalize it to a standard issue list, then validate each finding against the actual code so false positives are filtered out. The output is a validated issue set ready for a caller to fix. This command does not fix anything.

Copilot reasons from diff context and has a high false-positive rate, so the validation pass is the step that makes the output trustworthy — not optional polish.

## Current State

**Current branch:**
!`git rev-parse --abbrev-ref HEAD`

## Instructions

### Step 1: Locate the PR

Get the PR number for the current branch:

```bash
gh pr view --json number -q .number
```

If there is no PR for this branch, say so and stop.

### Step 2: Fetch the Most Recent Copilot Review

Copilot posts a new review on each run, so the PR usually carries several. **Take only the latest** — older ones describe code that has since changed, and their findings are frequently already fixed.

Get the most recent Copilot review's ID and body:

```bash
gh api --paginate --slurp "repos/{owner}/{repo}/pulls/{pr_number}/reviews?per_page=100" --jq 'add | [.[] | select((.user.login // "") | ascii_downcase | contains("copilot"))] | sort_by(.submitted_at) | last | {id, body, submitted_at}'
```

Then fetch the inline comments belonging to **that review only**:

```bash
gh api --paginate "repos/{owner}/{repo}/pulls/{pr_number}/reviews/{review_id}/comments?per_page=100" --jq '.[] | {path, line, position, body}'
```

Details that matter in these commands:

- **`gh api` only auto-substitutes `{owner}`, `{repo}`, and `{branch}`.** Substitute `{pr_number}` and `{review_id}` yourself with the real values, or the call 404s.
- **`--paginate` is required.** The reviews endpoint returns 30 per page in ascending id order, so without it page 1 holds the *oldest* reviews and `last` silently returns a stale Copilot review on any PR with more than 30. That failure is invisible — you get a plausible-looking review describing code that has since changed.
- **`--slurp` returns an array of pages, so `add` flattens it** before the aggregate sort. Without `add`, `sort_by | last` runs per page and emits one result per page.
- **`(.user.login // "")` guards against a review from a deleted account**, where `user` is null and a bare `.user.login` hard-errors the whole query.

The review body holds the overview/summary; the review comments hold the inline code feedback. You need both.

If no Copilot review exists on the PR, the query returns `{"id":null,...}` rather than empty output — treat a null id as "no Copilot review", say so, and stop.

### Step 3: Normalize and Output

Map each finding to a standard severity so downstream commands can consume it:

- **CRITICAL** — security vulnerabilities, data loss, crashes
- **HIGH** — bugs, incorrect behavior, resource leaks
- **MEDIUM** — missing validation, unhandled edge cases, performance concerns
- **LOW** — style, naming, documentation, minor cleanups

Output:

```
## Copilot Review

**PR:** #[number]
**Review submitted:** [submitted_at]
**Issues found:** [count by severity]

### Summary
[Copilot's review body verbatim, or "none" if empty]

### CRITICAL
- **file:line** — [description] — [Copilot's suggested fix, if any]

### HIGH
...

### MEDIUM
...

### LOW
...
```

If Copilot's latest review found no issues, state that the PR is clean per Copilot and stop.

### Step 4: Validate the Findings

Run the normalized findings through validation to filter false positives:

```
Skill(skill="rc-toolkit:validate-review")
```

The findings from Step 3 are already in the conversation, which is exactly the input `validate-review` expects. It reads the actual source for each finding, confirms the genuine ones, and dismisses the false positives with reasons. Its validated report replaces the Step 3 output as this command's final result.

This is the last step, so invoking `Skill()` directly is fine — nothing needs the turn afterward.

## Rules

- **Latest review only.** Never merge findings across multiple Copilot reviews — earlier ones reference stale code.
- **Do not drop findings before validation.** Carry every finding Copilot raised, including ones you suspect are false positives, from Step 2 into Step 3. Validation is where issues get dismissed — with a documented reason — so nothing disappears silently. Do not pre-filter in Steps 2–3.
- **Do not fix anything.** This command fetches and validates only; fixing is the caller's job.
- **Preserve Copilot's wording** for each issue rather than paraphrasing it away — validation needs the original claim to check it against the code.
- **Assign severity by impact, not by Copilot's tone.** Copilot phrases most findings uniformly; judge from what the issue would actually cause.
