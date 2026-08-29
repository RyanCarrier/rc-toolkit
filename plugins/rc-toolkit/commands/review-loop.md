---
description: Plan and fix review issues in a loop until no actionable issues remain
model: opus
context: none
allowed-tools: AskUserQuestion, Agent, Read, Write, Edit, Bash(git:*), Bash(gh pr view:*), Bash(gh issue create:*), Bash(date:*)
argument-hint: [medium] [low] [budget N] [hours N]
---

# Review Loop

You are a **loop controller**, not a reporter. Your turn does not end until the loop reaches a stop condition or the user stops you. After every review you triage, count, and — in the same response — act. **A response that contains a count but no subsequent tool call is a bug.**

Each iteration runs: **review → triage → count → plan (≤5) → implement → delta re-review → count**.

## Design Rules

These rules are why the loop is shaped the way it is. Do not relax them.

1. **Only the first review is a full review.** LLM reviewers are non-deterministic: a fresh pass over a large diff always finds something, whether or not the last fixes were good. Every re-review covers only the commits the previous iteration made, verifies each planned fix, and looks for regressions. It never re-reads unchanged code.
2. **Only mechanical, in-scope fixes are fixed.** A finding that needs a product or design call is a **DECISION** for the user. A finding outside the PR's stated intent is **PARKED**. Neither is fixed by the loop, and neither counts toward the total.
3. **Stop on convergence, not on zero.** The loop ends when the actionable count is zero, when the count stops falling, or when the iteration or time budget is spent. Then it asks the user once, with everything batched.
4. **Every disposition is written to a branch-keyed ledger** so nothing is re-litigated across iterations or across runs on the same branch.
5. **Ask late, ask once.** Do all the work that does not depend on the user, then ask one batched question. Exception: a decision that blocks a CRITICAL fix or more than half of the queue is asked immediately.

## Severity Threshold

- **Default:** TOTAL = CRITICAL + HIGH, counted over queued **FIX** items only.
- `medium` in `$ARGUMENTS` → also count MEDIUM. `low` → also count MEDIUM and LOW.
- DECISION and PARKED items are tracked separately and never count toward TOTAL.

## Budget

- **Iterations:** 3 by default. `budget N` in `$ARGUMENTS` overrides.
- **Wall clock:** 2 hours by default, measured from Step 0. `hours N` overrides.
- **Fixes per iteration:** 5. CRITICAL first, then HIGH, then MEDIUM, then LOW.

## Loop State

State lives under `.claude/review-loop/` in the target repo. **Never stage or commit anything under it.**

| File | Owner | Purpose |
|---|---|---|
| `scope.md` | Step 0 | Branch, base, baseline HEAD, PR title/body, the PR's file list, threshold, budget, `loop_start` |
| `ledger.md` | Orchestrator | Branch-keyed. Entries: `wont-fix`, `decision (pending)`, `decision (answered: …)`, `parked (pending | issue <url> | dropped | pulled)`. An entry marked `queued as FIX` or `pulled` is back in the loop and is not a drop match. Kept across runs on the same branch |
| `queue.md` | Orchestrator | Validated FIX items not yet fixed |
| `plan.md` | Planner | Current iteration's plan |
| `history.md` | Orchestrator | One line per iteration: counts and fix commit range. Drives stall detection |

`<N>` in subagent prompts is the current iteration number. Substitute it before calling — subagents do not share your context.

## Non-Interactive Mode

If the prompt that invoked you says not to prompt the user (for example `auto-branch`): skip the early decision gate in Step 2 (fixes that depend on a pending decision stay queued and are reported), and treat Step 6 as write-the-report-and-stop. Pending decisions and parked items go in the report unanswered.

## Instructions

### Step 0: Initialize — RUN ONCE, BEFORE ANYTHING ELSE

1. **Exclude the scratch directory from git.** Resolve the exclude file with `git rev-parse --git-path info/exclude` — do not hardcode `.git/info/exclude`; in a linked worktree `.git` is a file. If the resolved file does not list `.claude/review-loop/`, append that line.

2. **Keep or reset the ledger.** Read the current branch with `git branch --show-current`. Then:
   - `ledger.md` exists and its first line is `# Review-loop ledger — branch: <this branch>` → **keep it.** This is a re-run on the same branch; earlier decisions stand.
   - `ledger.md` exists for another branch, or has no branch header → archive it to `ledger.prev.md` and write a fresh one with the header.
   - A legacy `wont-fix.md` exists → archive it to `wont-fix.prev.md`. Do not import it; it has no dispositions.
   - Nothing exists → write a fresh `ledger.md` with the header.

3. **Write `scope.md`.** Gather and record:
   - `base`: `gh pr view --json baseRefName -q .baseRefName`; fall back to `main`, then `master`.
   - `baseline_head`: `git rev-parse HEAD`.
   - `files`: `git diff --name-only <base>...HEAD` — the PR's file set. Fixes stay inside it.
   - `intent`: `gh pr view --json title,body`; if there is no PR, use `git log <base>..HEAD --format='%s%n%b'`.
   - `threshold`, `budget`, `hours` from `$ARGUMENTS` or the defaults above.
   - `loop_start`: `date -u +%Y-%m-%dT%H:%M:%SZ`.

4. **Reset per-run files.** `plan.md` → `# (cleared)`. `queue.md` → `# Queue`. `history.md` → `# History`. Iteration counter **N = 1**.

### Step 1: Baseline Review — full PR, once

If a validated multi-PR review is already in this conversation, reuse it: say so and go to Step 2.

Otherwise run it through a subagent. **Do not call `Skill()` directly** — it takes over the turn and prevents Step 2 from running in the same response.

```
Agent(
  description="Multi-PR review",
  prompt="Run a full multi-PR review with validation. Invoke Skill(skill='rc-toolkit:multi-pr-review', args='--scope .claude/review-loop/scope.md --ledger .claude/review-loop/ledger.md'). Return the complete validated results exactly as produced — every issue with severity, file, line, description, reviewer attribution, and disposition (FIX / DECISION / OUT-OF-SCOPE), plus the ledgered-skipped list."
)
```

### Step 2: Triage and Count — MANDATORY AFTER EVERY REVIEW

Do all of this in one response, and end it with a tool call.

1. **Route every VALID issue by disposition:**
   - **FIX** → append to `queue.md` (file, line, severity, substance, reviewers). Skip anything already in the queue or the ledger, matching on file + substance — line numbers drift.
   - **DECISION** → append to `ledger.md` as `decision (pending)` with the brief: question, options, recommendation, and the issue it came from.
   - **OUT-OF-SCOPE** → append to `ledger.md` as `parked` with the reviewer's reason.
2. **Count the queue at the threshold:**
   `CRITICAL: N, HIGH: N, MEDIUM: N, LOW: N → TOTAL: N | decisions pending: N | parked: N | ledgered: N`
   On the baseline review, append `baseline: unresolved <TOTAL>` to `history.md` — Step 5's stall check compares against it.
3. **Early decision gate.** A pending decision *blocks* a queued FIX item when the item's correct fix depends on the answer — the brief's `Blocks:` field names them; add any you can see yourself (same file, same behaviour). If a pending decision blocks a CRITICAL fix, or blocks more than half of the queue, go to Step 6a now, apply the answers, then continue here. Skipped in non-interactive mode.
4. **Act:**
   - TOTAL = 0 → go to Step 5's stop handling.
   - TOTAL > 0 → call the Agent tool for Step 2.5 in this same response. Do not end the turn. Do not ask the user. Do not summarize.

### Step 2.5: Plan

Select up to **5** items from the queue in severity order (CRITICAL → HIGH → MEDIUM → LOW; review order within a severity). Leave the rest queued. Do not skip planning for a small or trivial-looking set — the plan's blast-radius evidence is what keeps this iteration's fixes from becoming the next iteration's findings.

```
Agent(
  description="Plan fixes",
  prompt="This is iteration <N> of the review loop. Build a plan of attack for the following validated, in-scope FIX issues (at most 5):\n\n<PASTE THE SELECTED ISSUES WITH SEVERITY, FILE, LINE, DESCRIPTION>\n\nInvoke Skill(skill='rc-toolkit:plan-fixes'). The scope file is .claude/review-loop/scope.md and the ledger is .claude/review-loop/ledger.md. Return the summary it produces — fix count, won't-fix count, needs-decision count, dropped-by-ledger count, and interactions."
)
```

### Step 2.6: Reconcile the Ledger

Read `plan.md` before implementing anything.

1. Copy every `## Won't Fix` entry into `ledger.md` as `wont-fix` (file, substance, iteration, rationale), and remove that item from the queue. Deduplicate on file + substance.
2. Copy every `## Needs Decision` entry into `ledger.md` as `decision (pending)` with its brief, and remove that item from the queue.
3. **Disposition check.** Every item you passed to the planner must be in `## Fixes`, `## Won't Fix`, `## Needs Decision`, or `## Deferred` (deferred items simply stay queued). One missing from all four stays in the queue — note it; do not ledger it.
4. If `## Fixes` is empty, append `iteration <N>: fixed 0, blocked 0, range none` to `history.md`, skip Steps 3 and 4, and go to Step 5.

Won't-fix and needs-decision authority belongs to the planner; the ledger write belongs to you. The implementation agent never touches the ledger.

### Step 3: Implement

Record `pre_fix = git rev-parse HEAD`, then:

```
Agent(
  description="Implement fix plan",
  prompt="Implement the fix plan at .claude/review-loop/plan.md. Read the whole plan first, then implement each fix exactly as specified, in the plan's stated order, following existing code conventions.\n\nThe plan is the source of truth. Do not redesign a fix while implementing it; if a fix turns out to be impossible or clearly wrong once you are in the code, implement the rest and report that one as blocked.\n\nEdit only files the plan names. If a fix needs a file that is not in the file list in .claude/review-loop/scope.md, do not make that edit — report the fix as blocked with the file it needed. New or updated test files, and the fixtures or helpers a test needs, are always in scope.\n\nImplement each fix's test strategy. Respect the blast-radius notes: update the dependent callers and tests the plan names.\n\nAfter implementing, look for a pre-commit skill or command in the project (search available skills for 'pre-commit', 'lint', 'check', 'format') and use it if found; only infer tooling commands if none exists. Then commit and push. Do NOT stage anything under .claude/review-loop/. Report each FIX-N as done or blocked, with the reason."
)
```

After it returns, record `post_fix = git rev-parse HEAD`. Remove done items from the queue; blocked items stay. Append to `history.md`: `iteration <N>: fixed <n>, blocked <n>, range <pre_fix>..<post_fix>`. If a done item came from an answered decision or a pulled-in parked entry, update that ledger entry to `… — fixed in <post_fix>`.

If `post_fix == pre_fix`, nothing was committed: treat every fix as blocked, write `range none`, skip Step 4, and go to Step 5 — there is no delta to review.

### Step 4: Delta Re-Review

Review only what the iteration changed. Never re-run the full review here.

```
Agent(
  description="Multi-PR delta re-review",
  prompt="Run a multi-PR review in delta mode. Invoke Skill(skill='rc-toolkit:multi-pr-review', args='--range <pre_fix>..<post_fix> --plan .claude/review-loop/plan.md --scope .claude/review-loop/scope.md --ledger .claude/review-loop/ledger.md'). Return the validated results exactly as produced — the per-fix verification table (FIX-N: resolved / not resolved / regression) and every new issue with severity, file, line, reviewer attribution, and disposition."
)
```

### Step 5: Loop Check

1. **Increment N.** `M = N − 1` is the number of completed iterations. The budget compares `M`, not `N`.
2. **Route the delta results.** A FIX-N reported *not resolved* returns to the queue at its severity. Regressions and new FIX issues go to the queue. DECISION and OUT-OF-SCOPE go to the ledger exactly as in Step 2. Skip anything already queued or ledgered.
3. **Count** the queue at the threshold and write it:
   `CRITICAL: N, HIGH: N, MEDIUM: N, LOW: N → TOTAL: N | decisions pending: N | parked: N` (iteration M of budget B, elapsed H)
   Append `unresolved <TOTAL>` to this iteration's `history.md` line.
4. **Act, in this same response — first matching rule wins:**
   - **Clean:** TOTAL = 0 → output `LOOP COMPLETE: PR is clean after M iterations`, write the report, then Step 6 if there are pending decisions or parked items; otherwise stop.
   - **Stall:** TOTAL ≥ the previous count in `history.md` (the baseline on iteration 1), or this iteration fixed nothing and ledgered nothing → write the report, then Step 6.
   - **Budget:** M ≥ iterations budget, or elapsed ≥ hours → write the report, then Step 6.
   - **Otherwise:** call the Agent tool for Step 2.5.

### Step 6: Ask the User — batched, once

Print the report **before** asking, so an unattended run leaves a complete record whatever happens to the question. Then batch everything into as few `AskUserQuestion` calls as possible (4 questions per call). If there are more than 3 pending decisions, ask the 3 highest-severity ones plus the continue question first, then the rest.

**6a. Decisions** — one question per pending decision. Question = the brief's question. Options = the brief's concrete alternatives, recommended first and labelled `(Recommended)`, plus `Defer — leave as is`.

**6b. Continue?** — only when the loop stopped with TOTAL > 0:
- `Continue 1 more iteration` → budget += 1, go to Step 2.5.
- `Continue 3 more iterations` → budget += 3, go to Step 2.5.
- `Stop and report` → stop.

**6c. Parked items** — one multi-select question listing every `parked` entry not yet resolved, with options `File as GitHub issues`, `Pull into this loop`, `Drop`.

**Apply the answers:**
- Decision answered → update its ledger entry to `decision (answered: <choice>)`. If the choice needs code, add a FIX item to the queue tagged `from-decision` and mark the entry `decision (answered: <choice> — queued as FIX)` so the validator and planner do not drop it; it is planned in the next iteration if the loop continues, or listed under "Follow-up" in the final report if it does not.
- `Defer` → the entry stays `pending`; it is not re-asked this run.
- After applying every answer, re-print the `### Decisions needed`, `### Parked`, and `### Follow-up` sections so the answers, issue URLs, and queued follow-ups are on screen.
- Then: if the queue now has items at the threshold and the budget is not exhausted (M < iterations, elapsed < hours), go to Step 2.5 — do not leave `from-decision` fixes for later when the loop can still run. Otherwise list them under "Follow-up" in the report and stop.
- Parked → `File as GitHub issues`: open one issue per item with `gh issue create` (title from the substance, body from the finding and the reason it is out of scope) and record the URL in the ledger entry. `Pull into this loop`: move to the queue as FIX and mark the entry `parked (pulled)`. `Drop`: mark `parked (dropped)`.

## Report Format

```
## Review-loop report — <branch>

Iterations: M of B · elapsed: H · stop reason: <clean | stall | budget | user>

### Fixed
| Iter | Commits | Fixes |
| ... |

### Remaining (in scope, unfixed)
- SEVERITY — file:line — substance — why it is still open

### Decisions needed
- file — question — options — recommendation — status (pending | answered: …)

### Parked (out of scope)
- file — substance — reason — status (pending | issue <url> | dropped)

### Won't fix
- file — substance — rationale (iteration N)

### Follow-up
- FIX items created from answered decisions but not yet implemented
```

## Rules

- **Every triage or loop check ends with a tool call, never with text.** The count and the action are one response.
- **Only FIX items are counted or planned.** Decisions and parked items are routed, never fixed by the loop.
- **Never expand scope.** A fix that needs a file outside `scope.md`'s file list is a decision, not a fix.
- **Delta re-review only.** The full review runs once, in Step 1.
- **Stall means stop.** A count that does not fall is the signal that the reviewers are finding new things, not that the code is getting worse. Report it; do not spend budget on it.
- **Always subtract the ledger before counting.** An issue reaches the ledger only through a planner disposition or a user answer; once there it is never re-planned.
- **Never skip planning**, even for a single issue.
- **The validate-review "Recommendations" section is informational.** Only the mechanical count decides the action.
- **Reuse an existing review** if one is already in the conversation.
- **Use subagents for every stage.** The orchestrator only routes, counts, decides, and writes the ledger. Never call `Skill()` from the orchestrator.
- **Never commit `.claude/review-loop/`.** If the implementation agent reports staging it, unstage it.
