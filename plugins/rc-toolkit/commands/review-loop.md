---
description: Iteratively fix review issues and re-review until only LOW severity remains
model: opus
context: none
---

# Review Loop

Run a multi-PR review, fix issues, and repeat until only LOW severity issues (or none) remain.

**You are an orchestrator running a loop. You MUST NOT stop after the first review. After every review and validation pass, you MUST evaluate the results and either continue fixing or explicitly declare the PR clean. Completing a single review+validate cycle is NOT the end of your job — it is only the input to your loop decision.**

## Instructions

### Step 1: Initial Review (or reuse existing)

If a multi-PR review has already been completed in this conversation — for example, the user ran `/multi-pr-review` immediately before invoking this command, or pasted validated review output into the prompt — **reuse those existing validated results as your starting state and skip running a fresh review.** State explicitly that you are reusing the existing review, then proceed to Step 2.

Otherwise, run the multi-PR review to get the current state:

```
Skill(skill="rc-toolkit:multi-pr-review")
```

Either way, you must have a set of validated review results before moving to Step 2.

### Step 2: Evaluate Results — THIS IS MANDATORY AFTER EVERY REVIEW

**WARNING: The validate-review step inside multi-pr-review produces a "Recommendations" section. That is NOT your loop decision. You MUST still perform the severity count below before deciding whether to stop or continue. Do not relay the review output and stop — that is a bug.**

After the review skill returns, you MUST perform this mechanical check:

1. **Count issues by severity.** Go through the validated results and count the number of CRITICAL, HIGH, and MEDIUM issues separately.
2. **Write the counts explicitly** in your response: `CRITICAL: N, HIGH: N, MEDIUM: N`
3. **Apply the rule:**
   - If CRITICAL + HIGH + MEDIUM = 0 → report that the PR is clean and stop. **This is the ONLY condition that allows you to stop.**
   - If CRITICAL + HIGH + MEDIUM > 0 → you MUST proceed to Step 3. **This includes cases where only MEDIUM issues remain. MEDIUM is not acceptable — only LOW is acceptable.**

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

**This is the same mechanical check as Step 2. Do not skip it.**

Track the number of fix+review iterations completed so far. Maintain an **iteration budget** that starts at **3**. The budget can be extended by the user (see below).

1. **Count issues by severity** from the new validated results: `CRITICAL: N, HIGH: N, MEDIUM: N`
2. **Apply the rule:**
   - If CRITICAL + HIGH + MEDIUM = 0 → report success and stop.
   - If CRITICAL + HIGH + MEDIUM > 0 **and** iterations completed < budget → go back to Step 3 with the new issues. **MEDIUM counts — it is NOT acceptable.**
   - If CRITICAL + HIGH + MEDIUM > 0 **and** iterations completed ≥ budget → **prompt the user** using `AskUserQuestion` (see below). Do NOT silently stop.

#### Iteration-budget exhausted: ask the user

When the iteration budget is exhausted with issues still remaining, call `AskUserQuestion` with one question and these three options:

- **"Continue 1 more iteration"** — extend the budget by 1 and resume at Step 3.
- **"Continue 3 more iterations"** — extend the budget by 3 and resume at Step 3.
- **"Stop and report"** — stop the loop and report the remaining issues for manual intervention.

Include the current iteration count and a brief summary of the remaining issue counts (`CRITICAL: N, HIGH: N, MEDIUM: N`) in the question header so the user can make an informed choice.

Apply the user's answer:
- If they pick "Continue 1 more iteration" → budget += 1, go to Step 3.
- If they pick "Continue 3 more iterations" → budget += 3, go to Step 3.
- If they pick "Stop and report" → stop and report.

If the budget is exhausted again later, prompt again with the same three options.

**Do not stop after receiving review results without performing the count. The loop continues until CRITICAL + HIGH + MEDIUM = 0, or the user explicitly chooses to stop at the budget-exhausted prompt.**

## Rules

- **Keep looping.** Your job is not done until CRITICAL + HIGH + MEDIUM = 0, or the user explicitly chooses to stop at the iteration-budget prompt. A single review+validate pass is never sufficient on its own — you must always perform the severity count and decide.
- **MEDIUM is not acceptable.** Only LOW may remain. If MEDIUM issues exist, you must loop.
- **The validate-review output is input to your decision, not the decision itself.** Even if validate-review says "needs-fixes" or "merge-ready", you must still count severities and apply the rule mechanically. Do not stop just because the review skill finished producing output.
- **Reuse an existing review** if one is already present in the conversation — do not waste a review run.
- Default iteration budget is 3. When exhausted with issues remaining, prompt the user via `AskUserQuestion` (continue 1 more / continue 3 more / stop). Never silently stop at the budget.
- Each iteration should make measurable progress — if an iteration fixes zero issues, stop and report the stall to the user (do not consume more of the budget on a stalled loop).
- Do not fix LOW severity issues. They are acceptable.
- **Use subagents** for the fix work (Step 3) to keep file edits and diffs out of the orchestrator context. Run the review (Step 4) directly from the orchestrator so the results are available for the loop decision without nested subagent depth.
