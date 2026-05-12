---
description: Iteratively fix review issues and re-review until only LOW severity remains
model: opus
context: none
allowed-tools: AskUserQuestion, Agent, Skill, Bash(git *)
argument-hint: [include low]
---

# Review Loop

You are a **loop controller**, not a reporter. Your turn does not end until actionable issues = 0 or the user explicitly stops you. After every review, you count severities and — in the same response — either spawn a fix agent or declare the PR clean. **A response that contains a severity count but no subsequent tool call is a bug.**

## Severity Threshold

- **Default:** TOTAL = CRITICAL + HIGH + MEDIUM. LOW issues are acceptable and ignored.
- **If the user included "low" in their arguments** (check if `$ARGUMENTS` contains "low"): TOTAL = CRITICAL + HIGH + MEDIUM + LOW. All severities must be fixed.

## Instructions

### Step 1: Initial Review (or reuse existing)

If a multi-PR review has already been completed in this conversation — for example, the user ran `/multi-pr-review` immediately before invoking this command, or pasted validated review output into the prompt — **reuse those existing validated results as your starting state and skip running a fresh review.** State explicitly that you are reusing the existing review, then proceed to Step 2.

Otherwise, run the multi-PR review via a subagent so the results return to you (the orchestrator) for evaluation. **Do NOT use Skill() directly** — Skill() takes over the current turn and prevents you from continuing with Step 2 in the same response.

```
Agent(
  description="Multi-PR review",
  prompt="Run a full multi-PR review with validation. Invoke Skill(skill='rc-toolkit:multi-pr-review'). Return the complete validated results exactly as produced — include every issue with its severity, file, line, and description."
)
```

Either way, you must have a set of validated review results before moving to Step 2.

### Step 2: Evaluate Results and Act — MANDATORY AFTER EVERY REVIEW

After the review skill returns, perform this mechanical check and **immediately act on the result in the same response** — do not end your turn between the count and the action:

1. **Count issues by severity.** Go through the validated results and count each severity level separately.
2. **Write the counts explicitly:** `CRITICAL: N, HIGH: N, MEDIUM: N, LOW: N → TOTAL: N` (compute TOTAL per the severity threshold above)
3. **In the same response, take exactly one of these actions:**
   - If TOTAL = 0 → output "LOOP COMPLETE: PR is clean" and stop.
   - If TOTAL > 0 → **immediately call the Agent tool** (Step 3 below) in this same response. Do not end your turn. Do not ask the user. Do not summarize what you plan to do next. The Agent tool call must appear in the same response as the severity count.

**The only valid response after a non-zero count is a tool call.** If you find yourself writing a message to the user about what issues exist without simultaneously spawning the fix agent, you are bugging out. The count and the Agent call are one atomic action.

### Step 3: Fix Issues

Your Step 2 response MUST include this Agent tool call when TOTAL > 0. This is not a separate step you "proceed to" — it is part of the same response as your severity count.

```
Agent(
  description="Fix review issues",
  prompt="You have the following review issues to fix:\n\n<PASTE THE CRITICAL/HIGH/MEDIUM ISSUES HERE>\n\nFix these issues following existing code conventions. After fixing, check for a pre-commit skill or command in the project first (search available skills for 'pre-commit', 'lint', 'check', 'format') and use it if found — only fall back to inferring tooling commands if no skill exists. Then commit and push. Report what you fixed.\n\nFor each fix, consider whether a test would help prevent the issue from recurring. If the project has an existing test suite and adding a test is straightforward, write one. Don't force tests where they don't fit, but a targeted regression test for a bug fix or a unit test for a logic error is valuable."
)
```

Pass the specific issues into the subagent prompt.

### Step 4: Re-Review

After the fix subagent completes, run the multi-PR review via a subagent so the results return to you for evaluation. **Do NOT use Skill() directly** — Skill() takes over the current turn and prevents you from continuing with Step 5.

```
Agent(
  description="Multi-PR re-review",
  prompt="Run a full multi-PR review with validation. Invoke Skill(skill='rc-toolkit:multi-pr-review'). Return the complete validated results exactly as produced — include every issue with its severity, file, line, and description."
)
```

This keeps the review results in the orchestrator's context where they can be evaluated for the loop decision.

### Step 5: Loop Check — SAME RULES AS STEP 2

Track the number of fix+review iterations completed so far. Maintain an **iteration budget** that starts at **3**.

Perform the same atomic count-then-act as Step 2:

1. **Count issues:** `CRITICAL: N, HIGH: N, MEDIUM: N → TOTAL: N` (iteration M of budget)
2. **In the same response, take exactly one action:**
   - If TOTAL = 0 → output "LOOP COMPLETE: PR is clean after M iterations" and stop.
   - If TOTAL > 0 **and** iterations < budget → **immediately call the Agent tool** (Step 3) in this same response. No turn break. No summary. Just the tool call.
   - If TOTAL > 0 **and** iterations ≥ budget → **immediately call AskUserQuestion** in this same response (see below). Do NOT output a summary and stop.

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

- **Every evaluation (Step 2 / Step 5) must end with a tool call, never with text.** The severity count and the subsequent action (Agent call, AskUserQuestion, or "LOOP COMPLETE" declaration) are one atomic response. If your response after a review contains only text and no tool call, you have stopped incorrectly.
- **MEDIUM is not acceptable by default.** TOTAL = CRITICAL + HIGH + MEDIUM (or + LOW if user requested it). If TOTAL > 0, you loop.
- **The validate-review "Recommendations" section is informational only.** Ignore "merge-ready" / "needs-fixes" labels. Only the mechanical severity count determines your action.
- **Reuse an existing review** if one is already present in the conversation — do not waste a review run.
- Default iteration budget is 3. When exhausted, use `AskUserQuestion` — never silently stop.
- If an iteration fixes zero issues, stop and report the stall (do not consume more budget).
- Do not fix LOW severity issues unless the user requested it via arguments.
- **Use subagents** for fixes (Step 3). Run reviews (Step 4) directly from the orchestrator.
