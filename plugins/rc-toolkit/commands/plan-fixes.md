---
description: Build a consolidated plan of attack for fixing validated review issues
model: opus
argument-hint: [revise]
allowed-tools: Read, Write, Grep, Glob, Bash(git diff:*), Bash(git status:*), Bash(git log:*)
---

# Plan Fixes

You are a senior engineer producing a **plan of attack** for a set of validated review issues. You do not write any production code in this command — you produce a plan that another agent will implement and an adversarial critic will attack.

## Prerequisites

This command expects **validated** review results to be present in the conversation (from `/validate-review`, or `/multi-pr-review` which runs validation as its final step). If no validated results are present, tell the user to run a review first and stop.

## Mode

Determine the mode **from state on disk**, not from arguments alone — this command is usually invoked from a subagent where `$ARGUMENTS` is not substituted.

**You are in revision mode if either:**
- `.claude/review-loop/critique.md` exists and contains real verdicts (a `## Per-Fix Verdicts` section), **and** the current plan has not already answered it (no `## Revision Response` section), or
- the invoking prompt or `$ARGUMENTS` asks for a revision.

A critique file whose only content is `# (cleared)` is a cleared placeholder, not a critique — treat it as absent.

**Otherwise you are in initial-planning mode.** Build the plan from scratch via Steps 1–5.

Check for `.claude/review-loop/critique.md` before doing anything else, and state which mode you are in. In revision mode, follow "Revision Mode" below instead of Steps 1–4.

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

## Step 3: Identify Fix Interactions

Before writing per-issue fixes, look across the whole issue set for interactions:

- **Same-surface conflicts** — two issues in the same function or file whose fixes would collide or be applied on top of each other
- **Subsumption** — one fix that makes another issue disappear entirely
- **Shared root cause** — several symptoms produced by one underlying defect, which should be fixed once rather than patched N times
- **Ordering constraints** — a fix that must land before another to avoid an intermediate broken state

This cross-cutting view is the main reason the plan is a single document rather than N independent per-issue plans. Do not skip it.

## Step 4: Write the Plan

Write the plan to `.claude/review-loop/plan.md`, creating the directory if needed. Use this structure:

```markdown
# Fix Plan — Iteration [N]

**Issues planned:** [count]
**Dropped (won't-fix ledger):** [count]

## Dropped Issues
- **file** — [issue] — on ledger since iteration [N]: [rejection reason]

## Fixes

### FIX-1 — [severity] — file:line
**Issue:** [what the review flagged]
**Root cause:** [the actual underlying cause, which may differ from the flagged line]
**Proposed change:** [concretely what changes — which function, what the new behavior is. Specific enough that another engineer could implement it without re-deriving the design.]
**Blast radius:** [callers, dependents, tests found by grep — cite the searches. "None found" is a valid answer only if you actually searched.]
**Test strategy:** [what test proves this fix works and prevents regression, or an explicit reason no test fits]
**Risk:** [what could go wrong with this change]

### FIX-2 — ...

## Interactions & Ordering
- **Conflicts:** [fixes touching the same surface, and how to sequence them]
- **Subsumption:** [fixes that make other issues moot]
- **Shared root cause:** [issues collapsed into a single fix]
- **Required order:** [ordered list if any fix must precede another, otherwise "independent — any order"]

## Open Questions
[Anything genuinely ambiguous where the right fix depends on intent that isn't recoverable from the code. Empty is fine and expected.]
```

## Step 5: Report

Output a short summary to the conversation: how many fixes are planned, how many issues were dropped by the ledger, any interactions found, and the plan file path. Do not paste the entire plan back — it is on disk for the critic and implementer to read.

## Revision Mode

In revision mode, do this **instead of** Steps 1–4, then report per Step 5:

1. Read `.claude/review-loop/plan.md` and `.claude/review-loop/critique.md`.
2. For **every** critique finding, take a position — do not silently ignore any:
   - **REVISE** → change the plan to address the objection. Re-read code and re-grep if the critique surfaced a dependency you missed.
   - **REJECT-FIX** → replace the approach entirely with one that survives the objection.
   - **REJECT-ISSUE** → remove the fix entirely from the `## Fixes` section, and record `FIX-[n] — ... → ACCEPTED: removed from plan` in the Revision Response. Do not list it under "Moved to Ledger" — the loop controller already has it from the critique. Only dispute it (below) if you think the critic is wrong, in which case the fix stays in `## Fixes`.
   - **Disagree with the critique** → keep the fix, but state explicitly why the objection does not hold, citing code evidence. Disagreeing is allowed; ignoring is not.
3. **Never renumber FIX ids.** Ids are stable identifiers across the revision, not positions in a list. When you drop FIX-2, the remaining fixes keep their original ids and the plan simply has a gap — do **not** shift FIX-3 down into FIX-2. The loop controller decides what to ledger by checking which ids are still present in `## Fixes`, so renumbering makes it ledger the wrong issue: a dropped issue looks present and never gets ledgered (the loop then never terminates), or a shipping fix looks dropped and gets ledgered while its code change lands.

4. Rewrite `.claude/review-loop/plan.md` in place with the revised plan, adding a section:

```markdown
## Revision Response
- **FIX-[n]** — [critique finding] → [ACCEPTED: what changed | DISPUTED: why the objection does not hold, with evidence]

## Moved to Ledger
- **file** — [issue] — [why this should not be fixed]
```

**Always emit both headings**, even when there is nothing to put under them (write "none"). The loop controller reads both sections back to reconcile the won't-fix ledger — a missing heading is indistinguishable from a parse failure.

`## Moved to Ledger` is for fixes **you** decided to drop that the critic did not mark `REJECT-ISSUE` — for example, a fix made moot by another change. Do not repeat the critic's `REJECT-ISSUE` items here; the controller already has those.

**Every `## Revision Response` entry must lead with the `FIX-[n]` id** it responds to. The loop controller matches these ids against the critique's verdicts; prose-only entries force it to guess.

**Keeping a fix in `## Fixes` is what tells the controller it is shipping; removing it is what tells the controller to ledger it.** The plan's `## Fixes` section is the ground truth, so make it accurate: a fix you accepted a `REJECT-ISSUE` on must be fully removed, and a fix you disputed must remain. Mark the corresponding entry `DISPUTED` whenever you keep a fix the critic wanted dropped — that corroborates the decision, but the presence of the fix is what actually carries it.

## Rules

- **Plan, do not implement.** Write no production code in this command. The only file you write is the plan.
- **Never stage or commit the plan files.** `.claude/review-loop/` is loop scratch state, not part of the change under review.
- **Blast radius requires evidence.** Every fix entry must cite an actual grep, not an assumption about who calls the code.
- **One consolidated plan.** Do not emit per-issue plans that ignore each other.
- **Do not expand scope.** Plan fixes for the flagged issues only. If you notice an unrelated problem while reading, put it under "Open Questions" — do not add it as a fix.
- **Concrete over vague.** "Add validation" is not a plan. "Reject empty `name` in `parseConfig` before the map lookup at line 40, returning the existing `ConfigError`" is a plan.
