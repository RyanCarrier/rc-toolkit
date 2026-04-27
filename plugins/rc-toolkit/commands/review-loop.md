---
description: Iteratively fix review issues and re-review until only LOW severity remains
model: opus
context: none
---

# Review Loop

Run a multi-PR review, fix issues, and repeat until only LOW severity issues (or none) remain.

## Instructions

### Step 1: Initial Review

Run the multi-PR review to get the current state:

```
Skill(skill="rc-toolkit:multi-pr-review")
```

### Step 2: Evaluate Results

After the review completes, check the validated results for issues at CRITICAL, HIGH, or MEDIUM severity.

- If **no issues above LOW** exist: report that the PR is clean and stop.
- If **CRITICAL, HIGH, or MEDIUM issues** exist: proceed to Step 3.

### Step 3: Fix and Re-Review

Invoke the fix-rereview command to fix the issues, commit, push, and re-run the review:

```
Skill(skill="rc-toolkit:fix-rereview")
```

### Step 4: Loop Check

After fix-rereview completes (which includes its own re-review), evaluate the new results:

- If **no issues above LOW** remain: report success and stop.
- If **CRITICAL, HIGH, or MEDIUM issues** persist: go back to Step 3.
- If **3 iterations** have been completed without reaching clean: stop and report the remaining issues. Something may need manual intervention.

## Rules

- Maximum 3 iterations to avoid infinite loops.
- Each iteration should make measurable progress — if an iteration fixes zero issues, stop and report the stall to the user.
- Do not fix LOW severity issues. They are acceptable.
