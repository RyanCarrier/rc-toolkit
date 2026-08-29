---
description: Build a consolidated plan of attack for fixing validated review issues
model: opus
allowed-tools: Read, Write, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git rev-parse:*), Bash(gh pr view:*)
---

# Plan Fixes

You are a senior engineer producing a **plan of attack** for a set of validated review issues. You write no production code here — you produce a plan another agent implements exactly as written. There is no separate critique stage; the rigor lives here. Every decision carries enough justification and blast-radius evidence that a reader can judge it without re-deriving it.

## Prerequisites

**Validated** review results must be in the conversation (from `/validate-review`, or `/multi-pr-review`, which validates as its final step). If none are present, tell the user to run a review first and stop.

Plan only issues with disposition **FIX**. If you are handed a DECISION or OUT-OF-SCOPE issue, do not plan it — list it under `## Needs Decision` (with its brief) or `## Out of Scope` and move on.

## Step 1: Load the Ledger and Scope

Read `.claude/review-loop/ledger.md` if it exists (fall back to the legacy `.claude/review-loop/wont-fix.md`). Every entry there has already been dispositioned: `wont-fix` (rejected), `decision` (routed to the human), or `parked` (out of scope). An entry marked `queued as FIX` or `parked (pulled)` is the exception — that item is back in the loop; plan it.

**Drop any incoming issue that matches any other ledger entry** — same file and same underlying problem; line numbers drift, so match on substance. List what you dropped and why, citing the entry. Do not re-plan or re-litigate it.

Read `.claude/review-loop/scope.md` if it exists. Its file list is the boundary of this PR: **a fix is not allowed to edit a file outside it.** New or updated test files, and the fixtures or helpers a test needs, are always in scope. If the only correct fix needs any other outside file, the issue becomes a `## Needs Decision` entry (scope expansion is the user's call), not a fix.

If neither file exists, treat the ledger as empty and the scope as `git diff --name-only <base>...HEAD`.

## Step 2: Cap the Set

Plan at most **5** fixes per iteration. If handed more, keep CRITICAL → HIGH → MEDIUM → LOW order (review order within a severity), plan the first 5, and list the rest under `## Deferred` untouched — the loop carries them into the next iteration. A small, well-understood change set is what keeps this iteration's fixes from becoming the next iteration's findings.

## Step 3: Read the Code for Every Remaining Issue

For each issue, read the source and enough surrounding context to find the real root cause. The review's description is a starting point, not ground truth — validation confirmed the symptom, but the cause may sit elsewhere.

Establish the **blast radius** before proposing anything:

- `Grep` for callers of any function, method, or symbol the fix would change
- `Grep` for existing tests that exercise the affected code
- Note any public API, exported type, config key, or on-disk format the fix would alter

A fix proposed without knowing who depends on the code is a guess. Do the searches.

## Step 4: Decide the Disposition

- **Fix** — worth making, blast radius understood, all edits inside scope. Gets a FIX entry.
- **Won't fix** — the cure is worse than the disease: the behaviour is intentional, the risk of change exceeds the benefit, or the churn outweighs the value. Goes under `## Won't Fix`. **Near-permanent — earn it.** The loop copies every entry to the ledger and never looks at it again. Justify with file, substance, and concrete evidence.
- **Needs decision** — reading the code showed the fix depends on intent the code cannot supply. Use it when any of these holds:
  1. The fix changes user-visible behaviour or policy.
  2. The code contradicts a doc, ADR, or spec, and either could be right.
  3. Two reasonable fixes lead to different outcomes.
  4. The fix touches a public API, an on-disk or wire format, or store-facing copy.
  5. The fix needs a file outside the scope file list.

  Goes under `## Needs Decision` with a brief the human can answer in one click: `Question / Options (a) (b) (c) leave as is / Recommendation / Blocks: <FIX-N refs or none>`. Do not pick for them — the loop asks, records the answer in the ledger, and re-queues a fix if the answer needs one.

## Step 5: Identify Fix Interactions

Look across the whole set before writing per-issue fixes:

- **Same-surface conflicts** — two fixes in one function or file that would collide
- **Subsumption** — one fix that makes another issue disappear
- **Shared root cause** — several symptoms from one defect, fixed once
- **Ordering constraints** — a fix that must land before another to avoid a broken intermediate state

This cross-cutting view is why the plan is one document rather than N per-issue plans.

## Step 6: Write the Plan

Write to `.claude/review-loop/plan.md`, creating the directory if needed:

```markdown
# Fix Plan — Iteration [N]

**Issues planned:** [count]
**Won't fix:** [count]
**Needs decision:** [count]
**Deferred (cap):** [count]
**Dropped (ledger):** [count]

## Dropped Issues
- **file** — [issue] — ledger: [kind], iteration [N]: [rationale]

## Fixes

### FIX-1 — [severity] — file:line
**Issue:** [what the review flagged]
**Root cause:** [the actual cause, which may differ from the flagged line]
**Justification:** [why this is worth fixing and why this approach — defended with evidence]
**Proposed change:** [concretely what changes: which function, what the new behaviour is. Specific enough to implement without re-deriving the design.]
**Files:** [every file this fix edits — all must be in scope]
**Blast radius:** [callers, dependents, tests found by grep — cite the searches. "None found" is valid only if you searched.]
**Test strategy:** [the test that proves the fix and prevents regression, or why no test fits]
**Risk:** [what could go wrong]

### FIX-2 — ...

## Won't Fix
- **file** — [substance] — [full rationale, strong enough to remove this issue from the loop permanently]

## Needs Decision
- **file** — [substance] — Question: … · Options: (a) … (b) … (c) leave as is · Recommendation: … · Blocks: …

## Deferred
- [severity] **file:line** — [substance] (over the per-iteration cap; untouched)

## Out of Scope
- **file** — [substance] — [reason] (handed in with that disposition; not planned)

## Interactions & Ordering
- **Conflicts:** …
- **Subsumption:** …
- **Shared root cause:** …
- **Required order:** [ordered list, or "independent — any order"]

## Open Questions
[Ambiguities that did not rise to a decision. Empty is fine.]
```

**Always emit every heading**, even when empty (write "none"). The loop controller parses `## Fixes`, `## Won't Fix`, and `## Needs Decision`; a missing heading is indistinguishable from a parse failure.

## Step 7: Report

Output a short summary: fixes planned, won't-fix, needs-decision, deferred, dropped-by-ledger, interactions, and the plan path. Do not paste the plan back — it is on disk for the implementer.

## Rules

- **Plan, do not implement.** The plan is the only file you write.
- **Never stage or commit the plan files.** `.claude/review-loop/` is loop scratch state.
- **Only FIX issues get FIX entries.** Decisions and out-of-scope items are routed, not planned.
- **Never edit outside scope.** A fix that needs an outside file is a decision.
- **At most 5 fixes.** The rest are deferred, not squeezed in.
- **Blast radius requires evidence.** Cite the grep.
- **Justify decisions, not just changes.**
- **Every issue gets exactly one disposition:** FIX, Won't Fix, Needs Decision, Deferred, Out of Scope, or Dropped. An issue that vanishes from the plan stays in the loop forever.
- **Do not expand scope.** Unrelated problems go under Open Questions, not Fixes.
- **Concrete over vague.** "Add validation" is not a plan. "Reject empty `name` in `parseConfig` before the map lookup at line 40, returning the existing `ConfigError`" is a plan.
