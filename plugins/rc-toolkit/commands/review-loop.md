---
description: Plan and fix review issues in a loop until no actionable issues remain
model: opus
context: none
allowed-tools: AskUserQuestion, Agent, Read, Write, Edit, Bash(git:*)
argument-hint: [include low]
---

# Review Loop

You are a **loop controller**, not a reporter. Your turn does not end until actionable issues = 0 or the user explicitly stops you. After every review, you count severities and — in the same response — either start the fix pipeline or declare the PR clean. **A response that contains a severity count but no subsequent tool call is a bug.**

Each iteration runs: **review → count → plan → implement → re-review**.

## Severity Threshold

- **Default:** TOTAL = CRITICAL + HIGH + MEDIUM. LOW issues are acceptable and ignored.
- **If the user included "low" in their arguments** (check if `$ARGUMENTS` contains "low"): TOTAL = CRITICAL + HIGH + MEDIUM + LOW. All severities must be fixed.

## Loop State

The loop keeps state on disk under `.claude/review-loop/`:

- `plan.md` — the current iteration's fix plan (overwritten each iteration)
- `wont-fix.md` — the **won't-fix ledger**, appended to and never cleared *during* a run, reset by Step 0 *between* runs

`<N>` in the subagent prompts below is a placeholder — substitute the actual current iteration number before calling. Subagents do not share your context and cannot infer it, and the plan template stamps it into its output.

**The ledger is what makes this loop terminate.** The planner may decide an issue should not be fixed at all — the fix would be riskier than the bug, the behavior is intentional, or the churn outweighs the value. But the next review will flag that issue again. Without the ledger the loop re-plans and re-rejects the same issue until the budget runs out. Ledgered issues are subtracted from TOTAL on every subsequent count. Step 2.6 is the only place that writes the ledger, copying the plan's `## Won't Fix` section.

**Never stage or commit anything under `.claude/review-loop/`.** It is loop scratch state, not part of the change under review.

## Instructions

### Step 0: Initialize Loop State — RUN ONCE, BEFORE ANYTHING ELSE

The state files live in the **target repo**, so a previous run's state is still on disk. Reset it before starting:

1. **Exclude the scratch directory from git.** Resolve the exclude file's real path with `git rev-parse --git-path info/exclude` — **do not hardcode `.git/info/exclude`**, because in a linked worktree `.git` is a file rather than a directory and the hardcoded path does not exist. This toolkit is worktree-oriented, so that is a common case, not an edge one. Read the resolved path and, if it does not already list `.claude/review-loop/`, append that line and write it back. This is a local-only ignore — no repo change, no user-visible diff — and it is the only mechanical guard against the implementation agent's commit step sweeping loop scratch into the change under review. Prose reminders elsewhere in this command are backup, not the guard.

2. **Reset the ledger and plan file.** Always write a fresh empty `.claude/review-loop/wont-fix.md`, creating the directory if needed. If one already exists and is non-empty, it belongs to a *previous* loop run — most likely a different branch or PR — so archive it to `.claude/review-loop/wont-fix.prev.md` first. Carrying a stale ledger forward would silently discard issues from the current change that happen to resemble old rejections. Overwrite `plan.md` with `# (cleared)`.

3. **Record the iteration counter.** This run starts at **iteration 1**. You will pass the current iteration number into every subagent prompt — subagents do not share your context and cannot infer it.

Do this once per invocation, not once per iteration.

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

1. **Read the ledger.** Read `.claude/review-loop/wont-fix.md`. Step 0 created it, so it exists but may be empty — **an empty or unreadable ledger simply means nothing is ledgered yet, which is the normal state on iteration 1.** Do not treat a failed read as an error worth reporting. Discard any returned issue that matches a ledger entry (match on file + substance, not line number — lines drift between iterations).
2. **Count the remaining issues by severity.** Count each severity level separately, excluding ledgered issues.
3. **Write the counts explicitly:** `CRITICAL: N, HIGH: N, MEDIUM: N, LOW: N → TOTAL: N (ledgered/won't-fix: N)` (compute TOTAL per the severity threshold above)
4. **In the same response, take exactly one of these actions:**
   - If TOTAL = 0 → output "LOOP COMPLETE: PR is clean" (noting any ledgered issues) and stop.
   - If TOTAL > 0 → **immediately call the Agent tool** (Step 2.5 below) in this same response. Do not end your turn. Do not ask the user. Do not summarize what you plan to do next. The Agent tool call must appear in the same response as the severity count.

**The only valid response after a non-zero count is a tool call.** If you find yourself writing a message to the user about what issues exist without simultaneously spawning the next agent, you are bugging out. The count and the Agent call are one atomic action.

### Step 2.5: Plan the Fixes

Your Step 2 response MUST include this Agent tool call when TOTAL > 0. Do not skip planning — it runs on every iteration with actionable issues, regardless of how few or how simple they look. The plan is where every fix earns its justification and an evidence-based blast radius; that discipline is what keeps this iteration's fixes from becoming next iteration's issues.

```
Agent(
  description="Plan fixes",
  prompt="This is iteration <N> of the review loop. Build a plan of attack for the following validated review issues:\n\n<PASTE THE ACTIONABLE ISSUES HERE, WITH SEVERITY, FILE, LINE, AND DESCRIPTION>\n\nInvoke Skill(skill='rc-toolkit:plan-fixes'). Treat the issues above as the validated review results the command expects. Return the summary it produces — the fix count, won't-fix count, dropped-by-ledger count, and any interactions found."
)
```

Paste the actual issue text into the prompt, and substitute the real iteration number for `<N>` — the subagent does not share your context.

### Step 2.6: Ledger the Plan's Won't-Fix Decisions

After the planning agent returns, read `.claude/review-loop/plan.md` and reconcile the ledger **before** implementing anything:

1. **Copy every entry under the plan's `## Won't Fix` section into `.claude/review-loop/wont-fix.md`** (creating it if absent), one entry per issue, each with the file, the issue substance, the iteration number, and the plan's stated rationale. Deduplicate against entries already in the ledger and against each other, matching on file + substance. These issues are permanently out of the loop and subtracted from every future count.
2. **Sanity-check the disposition set.** Every actionable issue you passed to the planner must appear either as a fix in `## Fixes` or as an entry in `## Won't Fix`. If one is missing from both, do **not** ledger it — note it in your running summary and let the next re-review re-flag it. A silently dropped issue must stay in the loop, not vanish.
3. **If the ledger absorbed every actionable issue** (the plan's `## Fixes` section is empty), skip Steps 3 and 4 and go directly to Step 5's count with the ledger applied — nothing was implemented, so there is nothing to re-review.

**Won't-fix authority belongs to the planner; the ledger write belongs to you.** Never ledger an issue the plan still fixes, and never let the implementation agent touch the ledger.

### Step 3: Implement the Plan

Spawn the implementation agent. It implements **the plan**, not the raw review issues — the plan carries the justification and blast-radius analysis for every fix.

```
Agent(
  description="Implement fix plan",
  prompt="Implement the fix plan at .claude/review-loop/plan.md. Read the plan first, then implement each fix exactly as specified, following existing code conventions.\n\nThe plan is the source of truth — every fix states its justification and blast radius. Follow its stated ordering. Do not redesign a fix while implementing it; if a fix turns out to be impossible or clearly wrong once you are in the code, implement the rest and report that one as blocked rather than improvising a different approach.\n\nImplement the test strategy each fix specifies. Respect the plan's blast-radius notes — if it names dependent callers or tests, update them too.\n\nAfter implementing, check for a pre-commit skill or command in the project first (search available skills for 'pre-commit', 'lint', 'check', 'format') and use it if found — only fall back to inferring tooling commands if no skill exists. Then commit and push. Do NOT stage anything under .claude/review-loop/. Report what you implemented and anything you could not."
)
```

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

**Increment the iteration counter `N` now**, before any further planning. Every subagent prompt in the next round must carry the new value — if `N` stays at 1, round two's plan and ledger entries are all stamped with the wrong iteration and the ledger's history becomes unreadable.

Keep the two counters distinct: **`N` is the iteration about to run**, and **`M` is the number of iterations completed** — after the increment, `N = M + 1`. The budget check below compares `M` (completed) against the budget, not `N`. Conflating them ends the loop one round early. (`N` in the severity-count template below is an unrelated placeholder for a numeric count.)

Perform the same atomic count-then-act as Step 2, **including the ledger subtraction**:

1. **Read `.claude/review-loop/wont-fix.md` and discard matching issues.**
2. **Count issues:** `CRITICAL: N, HIGH: N, MEDIUM: N, LOW: N → TOTAL: N (ledgered: N)` (iteration M of budget — compute TOTAL per the severity threshold, which includes LOW only if the user asked for it)
3. **In the same response, take exactly one action:**
   - If TOTAL = 0 → output "LOOP COMPLETE: PR is clean after M iterations", list any ledgered won't-fix issues with their rationale, and stop.
   - If TOTAL > 0 **and** iterations < budget → **immediately call the Agent tool** (Step 2.5 — plan first, not fix) in this same response. No turn break. No summary. Just the tool call.
   - If TOTAL > 0 **and** iterations ≥ budget → **immediately call AskUserQuestion** in this same response (see below). Do NOT output a summary and stop.

#### Iteration-budget exhausted: ask the user

When the iteration budget is exhausted with issues still remaining, call `AskUserQuestion` with one question and these three options:

- **"Continue 1 more iteration"** — extend the budget by 1 and resume at Step 2.5.
- **"Continue 3 more iterations"** — extend the budget by 3 and resume at Step 2.5.
- **"Stop and report"** — stop the loop and report the remaining issues for manual intervention.

Include the current iteration count and a brief summary of the remaining issue counts (`CRITICAL: N, HIGH: N, MEDIUM: N, LOW: N`) in the question header so the user can make an informed choice.

Apply the user's answer:
- If they pick "Continue 1 more iteration" → budget += 1, go to Step 2.5.
- If they pick "Continue 3 more iterations" → budget += 3, go to Step 2.5.
- If they pick "Stop and report" → stop and report.

If the budget is exhausted again later, prompt again with the same three options.

**Do not stop after receiving review results without performing the count. The loop continues until TOTAL = 0 under the severity threshold in effect (CRITICAL + HIGH + MEDIUM, plus LOW if the user asked for it), or the user explicitly chooses to stop at the budget-exhausted prompt.**

## Rules

- **Every evaluation (Step 2 / Step 5) must end with a tool call, never with text.** The severity count and the subsequent action (Agent call, AskUserQuestion, or "LOOP COMPLETE" declaration) are one atomic response. If your response after a review contains only text and no tool call, you have stopped incorrectly.
- **MEDIUM is not acceptable by default.** TOTAL = CRITICAL + HIGH + MEDIUM (or + LOW if user requested it). If TOTAL > 0, you loop.
- **Always subtract the ledger before counting.** Once an issue reaches the ledger it must never be re-planned — skipping this is how the loop fails to terminate. An issue only reaches the ledger through the plan's `## Won't Fix` section, reconciled in Step 2.6.
- **Never skip the planning stage**, even for a single trivial-looking issue. The plan's justification and blast-radius requirements are where side effects get caught before implementation, and "trivial" fixes are a common source of them.
- **The validate-review "Recommendations" section is informational only.** Ignore "merge-ready" / "needs-fixes" labels. Only the mechanical severity count determines your action.
- **Reuse an existing review** if one is already present in the conversation — do not waste a review run.
- Default iteration budget is 3. When exhausted, use `AskUserQuestion` — never silently stop.
- If an iteration fixes zero issues **and adds nothing to the ledger**, stop and report the stall (do not consume more budget). An iteration that only ledgered issues counts as progress.
- Do not fix LOW severity issues unless the user requested it via arguments.
- **Use subagents for every stage** — review (1, 4), planning (2.5), implementation (3). The orchestrator only counts, decides, and writes the ledger. Never call `Skill()` directly from the orchestrator; it takes over the turn and breaks the atomic count-then-act rule.
- **Never commit `.claude/review-loop/`.** If the implementation agent reports staging it, that is a bug — unstage it.
