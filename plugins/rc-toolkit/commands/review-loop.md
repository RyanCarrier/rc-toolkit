---
description: Iteratively fix review issues and re-review until only LOW severity remains
model: opus
context: none
---

# Review Loop

Run a multi-PR review, fix issues, and repeat until only LOW severity issues (or none) remain.

**You are an orchestrator running a loop. You MUST NOT stop after the first review. After every review and validation pass, you MUST evaluate the results and either continue fixing or explicitly declare the PR clean. Completing a single review+validate cycle is NOT the end of your job — it is only the input to your loop decision.**

## Instructions

### Step 1: Initial Review

Run the multi-PR review to get the current state:

```
Skill(skill="rc-toolkit:multi-pr-review")
```

### Step 2: Evaluate Results — THIS IS MANDATORY AFTER EVERY REVIEW

After the review completes, you MUST parse the validated results and check for issues at CRITICAL, HIGH, or MEDIUM severity. Do not stop here. Do not summarize and exit. You must make a loop decision:

- If **no issues above LOW** exist → report that the PR is clean and stop. **This is the ONLY condition that allows you to stop early.**
- If **CRITICAL, HIGH, or MEDIUM issues** exist → you MUST proceed to Step 3. Do not stop.

### Step 3: Fix Issues

Use the **Agent tool** to spawn a subagent that **only** fixes the issues, runs pre-commit checks, commits, and pushes. Do NOT have the subagent run the review — that happens in Step 4.

```
Agent(
  description="Fix review issues",
  prompt="You have the following review issues to fix:\n\n<PASTE THE CRITICAL/HIGH/MEDIUM ISSUES HERE>\n\nFix these issues following existing code conventions. After fixing, check for a pre-commit skill or command in the project first (search available skills for 'pre-commit', 'lint', 'check', 'format') and use it if found — only fall back to inferring tooling commands if no skill exists. Then commit and push. Report what you fixed."
)
```

Pass the specific issues from Step 2 into the subagent prompt.

### Step 4: Re-Review

After the fix subagent completes, run the multi-PR review directly from the orchestrator:

```
Skill(skill="rc-toolkit:multi-pr-review")
```

This keeps the review results in the orchestrator's context where they can be evaluated for the loop decision.

### Step 5: Loop Check — MANDATORY

After the review completes, you MUST evaluate the validated results again:

- If **no issues above LOW** remain → report success and stop.
- If **CRITICAL, HIGH, or MEDIUM issues** persist → go back to Step 3 with the new issues.
- If **3 iterations** have been completed without reaching clean → stop and report the remaining issues. Something may need manual intervention.

**Do not stop after receiving review results without evaluating them. The loop continues until the exit condition is met.**

## Rules

- **Keep looping.** Your job is not done until the validated results contain only LOW severity issues (or none), or you hit the iteration limit. A single review+validate pass is never sufficient on its own — you must always evaluate and decide.
- Maximum 3 iterations to avoid infinite loops.
- Each iteration should make measurable progress — if an iteration fixes zero issues, stop and report the stall to the user.
- Do not fix LOW severity issues. They are acceptable.
- **Use subagents** for the fix work (Step 3) to keep file edits and diffs out of the orchestrator context. Run the review (Step 4) directly from the orchestrator so the results are available for the loop decision without nested subagent depth.
