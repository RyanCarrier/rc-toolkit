---
description: Validate PR review results by filtering out false positives and invalid issues
model: opus
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(gh pr view:*), Read, Grep, Glob
argument-hint: [--scope path] [--ledger path] [--range from..to] [--plan path]
---

# Validate Review Results

You are a senior engineer performing a second pass on code review findings. For each flagged issue, read the actual code and decide two things: **is it real**, and if so **what should happen to it** — a mechanical fix, a decision for the human, or parking as out of scope.

## Prerequisites

Review results must already be in the conversation (from `/multi-pr-review`, `/local-review`, `/quick-review`, etc.). If none are present, tell the user to run a review first and stop.

## Arguments

`$ARGUMENTS` may carry:

- `--scope <path>` — a scope file written by `review-loop` (branch, base, PR intent, PR file list). Without it, derive the scope in Step 0.
- `--ledger <path>` — a review-loop ledger. Issues matching a ledger entry are skipped.
- `--range <from>..<to>` — **delta mode**: only findings inside these commits count.
- `--plan <path>` — in delta mode, the fix plan whose fixes must be verified.

## Instructions

### Step 0: Establish Scope and Ledger

**Scope.** Read `--scope` if given. Otherwise derive it:

- Base branch: `gh pr view --json baseRefName -q .baseRefName`, falling back to `main` / `master`.
- Intent: `gh pr view --json title,body`; if there is no PR, `git log <base>..HEAD --format='%s%n%b'`.
- File list: `git diff --name-only <base>...HEAD`.

The scope is what the PR set out to do. It decides OUT-OF-SCOPE in Step 2b.

**Ledger.** Read `--ledger` if given and it exists. Drop every incoming issue that matches an entry on file + substance — line numbers drift, so match on what the issue says, not where. `wont-fix`, `decision (pending)`, `decision (answered: … leave as is)`, and `parked` (pending, issue, or dropped) entries are matches: they have already been routed. **Not** matches: an entry marked `queued as FIX` or `parked (pulled)` — that item is back in the loop, so validate it normally. List everything dropped under **Ledgered (skipped)** with the entry's kind and rationale.

**Range (delta mode).** When `--range` is given, compute `git diff --name-only <from>..<to>`. A finding whose location is not in those files is out of range — list it under **Out of range (skipped)** and do not validate it. Exception: keep a finding that claims code inside the range broke something outside it (a regression); mark it `(regression claim)`.

### Step 1: Extract Issues

Parse every issue from the review results. For each, note:

- File path and line number(s)
- Severity (CRITICAL / HIGH / MEDIUM / LOW or equivalent)
- Description
- Which reviewer(s) flagged it

### Step 2: Validate Each Issue

For every issue that survived Step 0, **read the actual source** with the Read tool. Check:

1. **Does the code actually have this problem?** Review tools flag on partial diff context and miss surrounding code that already handles the concern.
2. **Is the concern relevant to this codebase?** The pattern may be intentional, match project conventions, or be handled elsewhere.
3. **Is the suggested fix correct?** The issue can be real and the suggestion wrong.
4. **Is this style or preference disguised as a bug?** Filter subjective suggestions that were miscategorised.

Classify as:

- **VALID** — real and worth recording. Keep the original severity unless it is plainly wrong; if you change it, say why. Downgrade to LOW anything that is style, preference, hardening against a case the code cannot reach, or a hypothetical with no real code path.
- **INVALID** — false positive. Cite the code evidence.

**Single-reviewer gate.** When the review carries reviewer attribution and an issue was raised by only one reviewer:

- An **existence claim** (a symbol, file, flag, config key, or behaviour exists / is absent / says a specific thing) is VALID only if you confirm it in source. Otherwise INVALID, citing what you found.
- A **judgment claim** (a race, a missing check, a design flaw) stays VALID at its severity — reviewers catch different classes of issue, and requiring corroboration would suppress exactly what a second reviewer exists to find. Tag it `(single-reviewer)`.

### Step 2b: Give Every VALID Issue a Disposition

Exactly one of:

- **FIX** — in scope and mechanical: one clearly correct change, no product or design judgment required, all edits inside the scope file list.
- **DECISION** — in scope, but the right fix depends on intent the code cannot supply. Any of:
  1. The fix changes user-visible behaviour or policy (privacy, pricing, terms, distribution, what is collected or shown).
  2. The code contradicts a document, ADR, or spec, and either side could be the one that is right.
  3. Two reasonable fixes lead to different outcomes.
  4. The fix touches a public API, an on-disk or wire format, or store-facing copy.
  5. The fix needs a file outside the scope file list. New or updated test files, and the fixtures or helpers a test needs, are always in scope.
- **OUT-OF-SCOPE** — real, but not what this PR set out to do: a pre-existing defect the diff merely exposed, or an issue in code the PR did not change and its intent does not cover.

A **DECISION** must carry a brief the human can answer in one click:

```
Question: <one sentence>
Options: (a) <concrete change> · (b) <concrete change> · (c) leave as is
Recommendation: <letter> — <one-line reason>
Blocks: <file:line of FIX issues whose correct fix depends on this answer, or none>
```

An **OUT-OF-SCOPE** entry must state the reason in one line (pre-existing / outside PR files / outside PR intent).

### Step 3: Output the Validated Report

```
## Validated Review Results

**Original issues:** [count]
**Valid:** [count] (FIX [n] · DECISION [n] · OUT-OF-SCOPE [n])
**Invalid:** [count] · **Ledgered (skipped):** [count] · **Out of range (skipped):** [count]

---

### Fix verification            ← delta mode only, when --plan is given
| Fix | Status | Evidence |
| FIX-1 | resolved / not resolved / regression | what you read |

---

### Ledgered (skipped)
- **file** — [substance] — ledger: [kind] — [rationale]

### Out of range (skipped)
- **file:line** — [substance]

### INVALID (Filtered Out)
- ~~[severity]~~ **file:line** — [description]
  **Reason dismissed:** [code evidence]

---

### DECISION
- **file:line** — [description]
  **Validated by:** [what you checked]
  **Brief:** Question / Options / Recommendation / Blocks

### OUT-OF-SCOPE
- **file:line** — [description] — **Reason:** [one line]

---

### CRITICAL (FIX)
- **file:line** — [description + suggested fix] — flagged by [reviewers]
  **Validated by:** [what you checked]

### HIGH (FIX)
...

### MEDIUM (FIX)
...

### LOW (FIX)
...

---

### Recommendations
[Overall assessment: merge-ready, needs-fixes, or needs-rework]
[Action items for the FIX issues]
```

## Rules

- **Read before judging.** Never dismiss or confirm an issue without reading the code.
- **Be skeptical but fair.** Filter noise; keep what is real.
- **Preserve information.** Every original issue appears exactly once: INVALID, Ledgered, Out of range, or under a disposition. Nothing is silently dropped.
- **Disposition is mandatory** for every VALID issue. An issue with no disposition is a report bug.
- **A decision brief must be answerable in one click** — a real question, two or three concrete options, a recommendation.
- **Explain dismissals** with code evidence.
- **Do not add new issues.** Mention anything new briefly under a "Notes" section at the end.
