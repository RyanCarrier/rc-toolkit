# Review Loop — design notes and troubleshooting

For agents changing `commands/review-loop.md` (or the commands it chains) or diagnosing a run that will not converge. Read this before "fixing" the loop by adding iterations or loosening a rule — most of the obvious changes were the cause of the original problem.

## The incident this design comes from (2026-08-29/30)

Two runs of the pre-0.19 loop on one 63-file PR (again_replay #116):

| Run | Actionable per pass | Fixed | Ended by |
|---|---|---|---|
| A | 6 → 2 → 1 → 4 | 9 | user killed 16 agents at 07:49 after the budget prompt fired at 03:16 |
| B | 6 → 6 → 8 → 7 | 20 | user chose "Stop and report" |

Run B never converged. Total findings (incl. LOW) grew 12 → 12 → 15 → 17 while 20 fixes landed. Four of the final seven findings were consequences of the loop's own previous fixes, including a CRITICAL that was the third-generation descendant of a MEDIUM.

## Cause → rule

| Symptom | Root cause | What the loop does now | Where |
|---|---|---|---|
| Every pass found a *fresh* set of ~6 issues in unchanged code | Re-review was a full branch-vs-base review by non-deterministic reviewers. One unchanged line passed 7 reviews and was flagged on the 8th | Full review **once**; every re-review is `--range <pre_fix>..<post_fix>` and verifies each planned fix | `review-loop.md` Step 1 vs Step 4; `multi-pr-review.md` delta mode; `validate-review.md` out-of-range filter |
| Loop could not reach zero | Exit was `C+H+M = 0`; the consolidator's rubric made every edge case MEDIUM | Default threshold `C+H`; `medium` / `low` opt in. Stop on **stall** (count not falling), budget, or 2h — not only on zero | `review-loop.md` Severity Threshold, Step 5 |
| A MEDIUM became a HIGH became a CRITICAL over three iterations | A product decision (suppress vs declare location) was *fixed* instead of *asked*; each fix made the code more load-bearing, so reviewers rated residual defects higher. When finally asked, the owner wanted the opposite | `DECISION` disposition with a one-click brief; batched into one question; early gate only when a decision blocks a CRITICAL or > ½ the queue | `validate-review.md` Step 2b; `plan-fixes.md` Step 4; `review-loop.md` Step 6 |
| Same rejected issues re-flagged across runs | Step 0 archived any non-empty ledger as "a previous PR"; planner ledgered 0 of 20 because won't-fix was framed as near-forbidden | Ledger keyed by branch header, kept across runs; holds won't-fix, decisions, and parked items; passed to the validator so ledgered items never reach the count | `review-loop.md` Step 0, Loop State; `validate-review.md` Step 0 |
| PR grew every iteration (a file outside the original diff was pulled in) | No scope anchor; nothing flagged scope creep | `scope.md` records the PR's file list and intent; a fix needing an outside file is a decision; the reviewer brief reports scope creep | `review-loop.md` Step 0/3; `plan-fixes.md` Step 1; `multi-pr-review.md` Reviewer Brief |
| 6–8 fixes per pass, each a new review surface | No cap | Max 5 per iteration, CRITICAL → HIGH → MEDIUM → LOW | `review-loop.md` Step 2.5; `plan-fixes.md` Step 2 |
| Felt endless | ~50 min per healthy iteration; budget prompt fired after the user had gone to bed; one re-review took 6h | 2h wall clock; report is printed **before** any question so an unattended run leaves a record | `review-loop.md` Budget, Step 6 |
| Phantom HIGHs from one reviewer | Every finding counted regardless of evidence | Single-reviewer gate: an existence claim needs source confirmation; a judgment claim stays but is tagged | `validate-review.md` Step 2 |

## If a run still will not converge

Check in this order; each is a one-file read.

1. `.claude/review-loop/history.md` — is `unresolved` falling? If not, the loop should have stopped on **stall**. If it did not, the orchestrator skipped the Step 5 comparison.
2. `.claude/review-loop/history.md` `range` fields — are re-reviews delta (`<sha>..<sha>`) or `none`? A full review after iteration 1 means Step 4 was invoked without `--range`.
3. The validated report's `**Mode:**` line and `### Out of range (skipped)` — in delta mode, findings in untouched files must land there, not in the count.
4. `### DECISION` — are any of the queued FIX items really decisions (privacy, pricing, terms, doc-vs-code conflicts)? If they are being fixed, the validator's Step 2b criteria are being skipped.
5. `.claude/review-loop/ledger.md` — first line must name the current branch; entries marked `queued as FIX` / `parked (pulled)` are *in* the loop, all others are drop matches.
6. `**Reviewers:**` / `**Failed:**` — an `AGY REVIEW FAILED:` or empty reviewer is not a clean vote. See `agy-troubleshooting.md`.
7. `.claude/review-loop/scope.md` `files` — did any iteration edit a file outside it? That is a scope-expansion the plan should have escalated.

Do **not** respond to a non-converging run by raising the budget. The count not falling is the signal that the reviewers are sampling new findings from a large diff, not that the code is getting worse.

## Contracts between the commands

Change one side, change the other.

| Producer → consumer | Contract |
|---|---|
| `review-loop` → `multi-pr-review` | `--scope --ledger` (full) · `--range --plan --scope --ledger` (delta) |
| `multi-pr-review` → `validate-review` | same four flags passed through |
| `multi-pr-review` → `codex-review-pr` | `--base <ref>` + brief as the `codex review` `[PROMPT]` |
| `multi-pr-review` → `agy-review-pr` | `--range from..to` + brief appended to the `-p` prompt as `REVIEW BRIEF:` |
| `validate-review` → `review-loop` | headings `### DECISION`, `### OUT-OF-SCOPE`, `### Ledgered (skipped)`, `### Out of range (skipped)`, `### Fix verification`; severity sections suffixed `(FIX)`; decision brief fields `Question / Options / Recommendation / Blocks` |
| `plan-fixes` → `review-loop` | headings `## Fixes`, `## Won't Fix`, `## Needs Decision`, `## Deferred` (always emitted); FIX entries carry `**Files:**` |
| `review-loop` ↔ ledger | entry states: `wont-fix` · `decision (pending)` · `decision (answered: … [— queued as FIX] [— fixed in <sha>])` · `parked (pending | issue <url> | dropped | pulled)` |
| `auto-branch` → `review-loop` | invoked through an Agent with "do NOT prompt the user" → non-interactive mode (gate skipped, Step 6 = report and stop) |

## Known limitations

- The Claude reviewer (`pr-review-toolkit:review-pr`) computes its own diff; in delta mode it is bounded only by the brief and the validator's out-of-range filter.
- `codex review --base <sha>` with a commit SHA is assumed to work like a branch ref; confirm on the first real delta run.
- The early decision gate depends on the validator filling `Blocks:` — an empty field means the gate never fires and the decision waits for the batched question.
- Stall compares the whole-queue count, so a large baseline that the 5-per-pass cap works down slowly can look like a stall after one pass; the user is asked, not blocked.
- Reviewer failures (agy headless permission denials, Codex exceeding the foreground limit) still cost wall clock; the 2h budget bounds the damage but does not fix them.

## Where the design comes from

- Anthropic, Claude Code best practices — "A reviewer prompted to find gaps will usually report some, even when the work is sound … Tell the reviewer to flag only gaps that affect correctness or the stated requirements." https://code.claude.com/docs/en/best-practices
- GSD `/gsd-plan-review-convergence` — max cycles, stall detection on a non-decreasing count, single-reviewer consensus gate; `/gsd-audit-fix --max 5`. https://github.com/open-gsd/gsd-core
- AgentPatterns, Review-Then-Implement loop — "Cap automated fix attempts at one pass … Each extra automated pass risks new issues while masking the original." https://agentpatterns.ai/code-review/review-then-implement-loop/
- mattpocock/skills `code-review` — review the diff since a fixed point, against a spec; scope creep is a finding. https://github.com/mattpocock/skills
