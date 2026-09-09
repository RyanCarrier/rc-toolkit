---
description: Request a Copilot review on the current PR, wait for it, then validate and fix the findings
model: opus
---

# Copilot and Handle

Request a GitHub Copilot review on the current PR, wait for Copilot to post it, then hand off to `/rc-toolkit:handle-copilot-review` to validate the findings and fix the real ones.

Copilot reviews are asynchronous — GitHub queues the request and Copilot posts a review a few minutes later. This command requests the review, records a baseline so it can tell the *new* review apart from any older Copilot reviews already on the PR, polls until the new review lands, and then delegates the validate-and-fix work.

## Current State

**Current branch:**
!`git rev-parse --abbrev-ref HEAD`

## Instructions

### Step 1: Locate the PR

```bash
gh pr view --json number -q .number
```

If there is no PR for this branch, say so and stop.

### Step 2: Record the Baseline Copilot Review

Before requesting a new review, find the id of the most recent Copilot review already on the PR. New reviews always get strictly larger ids, so this baseline is how you recognize the review your request produces rather than a stale one that predates it.

```bash
gh api --paginate --slurp "repos/{owner}/{repo}/pulls/{pr_number}/reviews?per_page=100" --jq 'add | [.[] | select((.user.login // "") | ascii_downcase | contains("copilot"))] | sort_by(.id) | last | .id // 0'
```

Substitute `{pr_number}` yourself — `gh api` only auto-substitutes `{owner}` and `{repo}`. Record the printed number as `BASELINE_ID`; it is `0` when the PR has no Copilot review yet.

### Step 3: Request the Copilot Review

```bash
gh pr edit <pr_number> --add-reviewer "@copilot"
```

If this fails — for example, Copilot code review is not enabled for the repository, or your account lacks access — report the error and stop. There is nothing to wait for.

### Step 4: Wait for the New Review

Poll the reviews endpoint until a Copilot review with an id greater than `BASELINE_ID` appears. Copilot usually posts within 1–5 minutes. Run this with an extended Bash timeout (up to 10 minutes); it blocks until the review lands or the ~8-minute window elapses, and returns as soon as the review shows up.

```bash
PR=<pr_number>
BASELINE_ID=<baseline_id>
DEADLINE=$(( $(date +%s) + 480 ))
while :; do
  LATEST=$(gh api --paginate --slurp "repos/{owner}/{repo}/pulls/$PR/reviews?per_page=100" --jq "add | [.[] | select((.user.login // \"\") | ascii_downcase | contains(\"copilot\"))] | sort_by(.id) | last | .id // 0")
  if [ "${LATEST:-0}" -gt "$BASELINE_ID" ]; then echo "NEW_REVIEW $LATEST"; break; fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then echo "TIMEOUT"; break; fi
  sleep 30
done
```

- On `NEW_REVIEW`, go to Step 5.
- On `TIMEOUT`, the review has not arrived yet. If less than ~20 minutes have elapsed since Step 3, run the poll again. Otherwise, report that Copilot has not responded, tell the user they can re-run this command or check the PR, and stop.

### Step 5: Handle the Review

The new Copilot review is now the latest one on the PR, which is exactly what `handle-copilot-review` fetches. Hand off to it — this is the terminal step, so invoking `Skill()` directly is fine, nothing needs the turn afterward:

```
Skill(skill="rc-toolkit:handle-copilot-review")
```

It fetches and validates the latest Copilot review, then fixes the CRITICAL/HIGH/MEDIUM findings that survive validation.

## Rules

- **Baseline before requesting.** Always record `BASELINE_ID` (Step 2) *before* adding the reviewer, so the poll waits for the review your request triggers and never acts on a stale one.
- **Wait, do not busy-spin.** Keep the 30-second poll interval. Hammering the API adds nothing since Copilot posts on its own schedule.
- **Stop cleanly on timeout.** If Copilot never responds, report it and stop rather than handing off to `handle-copilot-review`, which would then act on a stale or nonexistent review.
- **Fixing happens in `handle-copilot-review`.** This command only requests, waits, and delegates. Do not fetch, validate, or fix the findings directly — that logic lives in `handle-copilot-review` and `get-copilot-review`, and duplicating it here would let the two drift apart.
