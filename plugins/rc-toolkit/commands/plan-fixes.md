---
description: Build a consolidated plan of attack for fixing validated review issues
model: opus
allowed-tools: Read, Write, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*)
---

# Plan Fixes

You are a senior engineer producing a **plan of attack** for a set of validated review issues. You do not write any production code in this command — you produce a plan that another agent will implement exactly as written. There is no separate critique stage; the rigor lives here. Every decision in the plan must carry enough justification and blast-radius evidence that a reader can judge it without re-deriving it.

## Prerequisites

This command expects **validated** review results to be present in the conversation (from `/validate-review`, or `/multi-pr-review` which runs validation as its final step). If no validated results are present, tell the user to run a review first and stop.

## Step 1: Load the Won't-Fix Ledger

Read `.claude/review-loop/wont-fix.md` if it exists. Every issue recorded there has already been examined and deliberately rejected in a previous iteration.

**Drop any incoming issue that matches a ledger entry** (same file and same underlying problem — line numbers drift, so match on substance, not line number). List what you dropped and why, citing the ledger. Do not re-plan a fix for an issue already on the ledger, and do not re-litigate the rejection.

If the ledger does not exist, treat it as empty.

## Step 2: Read the Code for Every Remaining Issue

For each issue that survived Step 1, read the actual source file and enough surrounding context to understand the real root cause. The review's description of the problem is a starting point, not ground truth — validation confirmed the symptom is real, but the root cause may sit somewhere other than the flagged line.

For each issue, also establish its **blast radius** before proposing a fix:

- `Grep` for callers of any function, method, or symbol the fix would change
- `Grep` for existing tests that exercise the affected code
- Note any public API, exported type, config key, or on-disk format the fix would alter

A fix proposed without knowing who depends on the code is a guess. Do the searches.

## Step 3: Decide Fix or Won't-Fix

Not every validated issue deserves a fix. For each issue, make an explicit disposition:

- **Fix** — the change is worth making and its blast radius is understood. It gets a FIX entry in the plan.
- **Won't fix** — the cure is worse than the disease: the behavior is intentional, the risk of change exceeds the benefit, or the churn outweighs the value. It goes under `## Won't Fix`.

**Won't-fix is near-permanent — earn it.** The loop controller copies every `## Won't Fix` entry to the ledger, which removes the issue from all future iterations with no further scrutiny. Justify each one thoroughly: name the file, the issue substance, and concrete evidence for why fixing costs more than not fixing. Use it when the fix is genuinely not worth making, not as a way to reduce work.

## Step 4: Identify Fix Interactions

Before writing per-issue fixes, look across the whole issue set for interactions:

- **Same-surface conflicts** — two issues in the same function or file whose fixes would collide or be applied on top of each other
- **Subsumption** — one fix that makes another issue disappear entirely
- **Shared root cause** — several symptoms produced by one underlying defect, which should be fixed once rather than patched N times
- **Ordering constraints** — a fix that must land before another to avoid an intermediate broken state

This cross-cutting view is the main reason the plan is a single document rather than N independent per-issue plans. Do not skip it.

## Step 5: Write the Plan

Write the plan to `.claude/review-loop/plan.md`, creating the directory if needed. Use this structure:

```markdown
# Fix Plan — Iteration [N]

**Issues planned:** [count]
**Won't fix:** [count]
**Dropped (won't-fix ledger):** [count]

## Dropped Issues
- **file** — [issue] — on ledger since iteration [N]: [rejection reason]

## Fixes

### FIX-1 — [severity] — file:line
**Issue:** [what the review flagged]
**Root cause:** [the actual underlying cause, which may differ from the flagged line]
**Justification:** [why this issue is worth fixing and why this approach over the alternatives — the decision, defended with evidence]
**Proposed change:** [concretely what changes — which function, what the new behavior is. Specific enough that another engineer could implement it without re-deriving the design.]
**Blast radius:** [callers, dependents, tests found by grep — cite the searches. "None found" is a valid answer only if you actually searched.]
**Test strategy:** [what test proves this fix works and prevents regression, or an explicit reason no test fits]
**Risk:** [what could go wrong with this change]

### FIX-2 — ...

## Won't Fix
- **file** — [issue substance] — [full rationale: why the fix costs more than the bug — strong enough to justify permanently removing this issue from the loop]

## Interactions & Ordering
- **Conflicts:** [fixes touching the same surface, and how to sequence them]
- **Subsumption:** [fixes that make other issues moot]
- **Shared root cause:** [issues collapsed into a single fix]
- **Required order:** [ordered list if any fix must precede another, otherwise "independent — any order"]

## Open Questions
[Anything genuinely ambiguous where the right fix depends on intent that isn't recoverable from the code. Empty is fine and expected.]
```

**Always emit the `## Won't Fix` heading**, even when there is nothing under it (write "none"). The loop controller reads this section to update the won't-fix ledger — a missing heading is indistinguishable from a parse failure.

## Step 6: Report

Output a short summary to the conversation: how many fixes are planned, how many issues were marked won't-fix, how many were dropped by the ledger, any interactions found, and the plan file path. Do not paste the entire plan back — it is on disk for the implementer to read.

## Rules

- **Plan, do not implement.** Write no production code in this command. The only file you write is the plan.
- **Never stage or commit the plan files.** `.claude/review-loop/` is loop scratch state, not part of the change under review.
- **Blast radius requires evidence.** Every fix entry must cite an actual grep, not an assumption about who calls the code.
- **Justify decisions, not just changes.** Every fix carries why it is worth making and why this approach; every won't-fix carries why it is not worth making. The implementer and any human reader take the plan on its stated evidence.
- **Every issue gets exactly one disposition.** Each incoming issue must end up as a FIX entry, a `## Won't Fix` entry, or a ledger-dropped entry under `## Dropped Issues`. An issue that silently vanishes from the plan stays in the loop forever.
- **One consolidated plan.** Do not emit per-issue plans that ignore each other.
- **Do not expand scope.** Plan fixes for the flagged issues only. If you notice an unrelated problem while reading, put it under "Open Questions" — do not add it as a fix.
- **Concrete over vague.** "Add validation" is not a plan. "Reject empty `name` in `parseConfig` before the map lookup at line 40, returning the existing `ConfigError`" is a plan.
