---
description: Plan, critique, and fix review issues in a loop until no actionable issues remain
model: opus
context: none
allowed-tools: AskUserQuestion, Agent, Read, Write, Edit, Bash(git:*)
argument-hint: [include low]
---

# Review Loop

You are a **loop controller**, not a reporter. Your turn does not end until actionable issues = 0 or the user explicitly stops you. After every review, you count severities and — in the same response — either start the fix pipeline or declare the PR clean. **A response that contains a severity count but no subsequent tool call is a bug.**

Each iteration runs: **review → count → plan → adversarial critique → revise → implement → re-review**.

## Severity Threshold

- **Default:** TOTAL = CRITICAL + HIGH + MEDIUM. LOW issues are acceptable and ignored.
- **If the user included "low" in their arguments** (check if `$ARGUMENTS` contains "low"): TOTAL = CRITICAL + HIGH + MEDIUM + LOW. All severities must be fixed.

## Loop State

The loop keeps state on disk under `.claude/review-loop/`:

- `plan.md` — the current iteration's fix plan (overwritten each iteration)
- `critique.md` — the current iteration's adversarial critique (overwritten each iteration)
- `wont-fix.md` — the **won't-fix ledger**, appended to and never cleared *during* a run, reset by Step 0 *between* runs

`<N>` in the subagent prompts below is a placeholder — substitute the actual current iteration number before calling. Subagents do not share your context and cannot infer it, and both the plan and critique templates stamp it into their output.

**The ledger is what makes this loop terminate.** When the adversarial critic returns `REJECT-ISSUE` and the planner does not rebut it, that issue is deliberately not being fixed — but the next review will flag it again. Without the ledger the loop re-plans and re-rejects the same issue until the budget runs out. Ledgered issues are subtracted from TOTAL on every subsequent count. Step 2.7 is the only place that writes the ledger, after reconciling the critique against the planner's response.

**Never stage or commit anything under `.claude/review-loop/`.** It is loop scratch state, not part of the change under review.

## Instructions

### Step 0: Initialize Loop State — RUN ONCE, BEFORE ANYTHING ELSE

The state files live in the **target repo**, so a previous run's state is still on disk. Reset it before starting:

1. **Exclude the scratch directory from git.** Resolve the exclude file's real path with `git rev-parse --git-path info/exclude` — **do not hardcode `.git/info/exclude`**, because in a linked worktree `.git` is a file rather than a directory and the hardcoded path does not exist. This toolkit is worktree-oriented, so that is a common case, not an edge one. Read the resolved path and, if it does not already list `.claude/review-loop/`, append that line and write it back. This is a local-only ignore — no repo change, no user-visible diff — and it is the only mechanical guard against the implementation agent's commit step sweeping loop scratch into the change under review. Prose reminders elsewhere in this command are backup, not the guard.

2. **Reset the ledger and plan files.** Always write a fresh empty `.claude/review-loop/wont-fix.md`, creating the directory if needed. If one already exists and is non-empty, it belongs to a *previous* loop run — most likely a different branch or PR — so archive it to `.claude/review-loop/wont-fix.prev.md` first. Carrying a stale ledger forward would silently discard issues from the current change that happen to resemble old rejections. Overwrite `plan.md` and `critique.md` with `# (cleared)`.

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

Your Step 2 response MUST include this Agent tool call when TOTAL > 0. Do not skip planning — it runs on every iteration with actionable issues, regardless of how few or how simple they look.

**First, clear the previous iteration's critique.** Overwrite `.claude/review-loop/critique.md` with the single line `# (cleared)`. The planner detects revision mode by the presence of a critique, so a stale one left over from the last iteration would make fresh planning behave as a revision of a plan that no longer exists. Clear it every iteration before spawning the planner.

```
Agent(
  description="Plan fixes",
  prompt="This is iteration <N> of the review loop. Build a plan of attack for the following validated review issues:\n\n<PASTE THE ACTIONABLE ISSUES HERE, WITH SEVERITY, FILE, LINE, AND DESCRIPTION>\n\nThis is INITIAL planning, not a revision — ignore any existing critique.md. Invoke Skill(skill='rc-toolkit:plan-fixes'). Treat the issues above as the validated review results the command expects. Return the summary it produces — the fix count, dropped-by-ledger count, and any interactions found."
)
```

Paste the actual issue text into the prompt, and substitute the real iteration number for `<N>` — the subagent does not share your context.

### Step 2.6: Adversarial Critique

After the planning agent returns, **immediately** spawn the critic in the same response. The critic must be a **separate, fresh subagent** — it is only useful if it is independent of whoever wrote the plan.

```
Agent(
  description="Adversarially critique fix plan",
  prompt="This is iteration <N> of the review loop. Adversarially attack the fix plan at .claude/review-loop/plan.md. Invoke Skill(skill='rc-toolkit:adversarial-plan-review'). Read the plan and the source code yourself — do not trust the plan's characterization of the code, and verify its claimed blast radius with your own searches. Return the verdict counts and the headline objections."
)
```

### Step 2.7: Revise the Plan (bounded — one round only)

Read `.claude/review-loop/critique.md`, then do these two things **in order**. Revision runs first; the ledger is written once, afterward, from the reconciled result.

**1. Revise, unless every verdict is APPROVE.** If any fix has a `REVISE`, `REJECT-FIX`, **or `REJECT-ISSUE`** verdict, spawn one revision agent. `REJECT-ISSUE` counts because the reviser is the only thing that removes the rejected fix from `plan.md` — skip it and the orchestrator ledgers the issue while Step 3 implements the fix anyway from an untouched plan, shipping a change that no future review can surface.

```
Agent(
  description="Revise fix plan",
  prompt="This is iteration <N> of the review loop. Revise the fix plan to address the adversarial critique. This is a REVISION pass, not initial planning. Invoke Skill(skill='rc-toolkit:plan-fixes') with the argument 'revise'. The plan is at .claude/review-loop/plan.md and the critique at .claude/review-loop/critique.md. Every critique finding must be either accepted with a concrete plan change or explicitly disputed with code evidence. Return the summary."
)
```

**All-`APPROVE` is the only case that skips the revision agent.** Any other verdict mix requires it.

**2. Write the ledger — exactly once, from the reconciled final state.** Do this after the revision agent returns (or immediately, if none ran). Compute the set of issues to ledger as:

- **Start with** every `REJECT-ISSUE` verdict in `critique.md`.
- **Subtract any whose FIX-id is still present in the revised plan's `## Fixes` section.** This is the ground-truth test, and it is what decides: a fix still in the plan is about to be implemented, so ledgering it would subtract it from every future count while the code change ships — hiding a real issue. A fix absent from `## Fixes` was dropped, so it belongs in the ledger. **Decide from the plan's `## Fixes` section, not from the prose in `## Revision Response`.** A `DISPUTED` entry there is corroborating evidence, not the test; a reviser that drops a fix and writes nothing about it is behaving correctly, and inferring from silence would leave the issue unledgered and re-flagged forever.
- **Add** everything under the revised plan's `## Moved to Ledger` section. The reviser can drop a fix the critic never marked `REJECT-ISSUE` — for instance when addressing one objection makes another fix unnecessary.
- **Deduplicate** against entries already in `wont-fix.md` and against each other, matching on file + substance.

Append the result to `.claude/review-loop/wont-fix.md` (creating it if absent), one entry per issue, each with the file, the issue substance, the iteration number, and the rationale. These issues are permanently out of the loop and subtracted from every future count.

**Write the ledger from this reconciled set only.** Do not also append raw `REJECT-ISSUE` verdicts straight from the critique — that double-writes every entry and, worse, ledgers issues the reviser successfully argued should still be fixed.

**This is capped at one revision round.** Do not re-run the critic on the revised plan and do not loop plan↔critique. The outer review loop is the mechanism for catching anything the revised plan still gets wrong.

**If the ledger absorbed every actionable issue** (nothing remains in the plan to implement), skip Step 3 and go directly to Step 5's count with the ledger applied.

### Step 3: Implement the Plan

Spawn the implementation agent. It implements **the plan**, not the raw review issues — the plan is what survived adversarial critique.

```
Agent(
  description="Implement fix plan",
  prompt="Implement the fix plan at .claude/review-loop/plan.md. Read the plan first, then implement each fix exactly as specified, following existing code conventions.\n\nThe plan is the source of truth — it has already been adversarially reviewed for correctness and side effects. Follow its stated ordering. Do not redesign a fix while implementing it; if a fix turns out to be impossible or clearly wrong once you are in the code, implement the rest and report that one as blocked rather than improvising a different approach.\n\nImplement the test strategy each fix specifies. Respect the plan's blast-radius notes — if it names dependent callers or tests, update them too.\n\nAfter implementing, check for a pre-commit skill or command in the project first (search available skills for 'pre-commit', 'lint', 'check', 'format') and use it if found — only fall back to inferring tooling commands if no skill exists. Then commit and push. Do NOT stage anything under .claude/review-loop/. Report what you implemented and anything you could not."
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

**Increment the iteration counter `N` now**, before any further planning. Every subagent prompt in the next round must carry the new value — if `N` stays at 1, round two's plan, critique, and ledger entries are all stamped with the wrong iteration and the ledger's history becomes unreadable.

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
- **Always subtract the ledger before counting.** Once an issue reaches the ledger it must never be re-planned — skipping this is how the loop fails to terminate. An issue only reaches the ledger after Step 2.7's reconciliation, so a `REJECT-ISSUE` the planner successfully disputed stays in the loop and gets fixed.
- **Never skip the plan/critique stages**, even for a single trivial-looking issue. The critique is where side effects get caught, and "trivial" fixes are a common source of them.
- **The critic is a separate subagent from the planner.** Never have one agent write a plan and critique its own work — the independence is the entire point.
- **Planning is bounded at one revision round per iteration.** Do not loop plan↔critique inside an iteration. The outer loop catches what the revised plan misses.
- **The validate-review "Recommendations" section is informational only.** Ignore "merge-ready" / "needs-fixes" labels. Only the mechanical severity count determines your action.
- **Reuse an existing review** if one is already present in the conversation — do not waste a review run.
- Default iteration budget is 3. When exhausted, use `AskUserQuestion` — never silently stop.
- If an iteration fixes zero issues **and adds nothing to the ledger**, stop and report the stall (do not consume more budget). An iteration that only ledgered issues counts as progress.
- Do not fix LOW severity issues unless the user requested it via arguments.
- **Use subagents for every stage** — review (1, 4), planning (2.5), critique (2.6), revision (2.7), implementation (3). The orchestrator only counts, decides, and writes the ledger. Never call `Skill()` directly from the orchestrator; it takes over the turn and breaks the atomic count-then-act rule.
- **Never commit `.claude/review-loop/`.** If the implementation agent reports staging it, that is a bug — unstage it.
