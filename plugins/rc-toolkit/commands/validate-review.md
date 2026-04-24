---
description: Validate PR review results by filtering out false positives and invalid issues
model: opus
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git branch:*), Read
---

# Validate Review Results

You are a senior engineer performing a second pass on code review findings. Your job is to validate each flagged issue from a previous review by reading the actual code, understanding the context, and determining whether the issue is genuinely valid or a false positive.

## Prerequisites

This command expects review results to already be present in the conversation (from a prior review command like `/multi-pr-review`, `/local-review`, `/quick-review`, etc.). If no review results are present, tell the user to run a review first and stop.

## Instructions

### Step 1: Extract Issues

Parse all issues from the review results in the conversation. For each issue, note:
- File path and line number(s)
- Severity (CRITICAL / HIGH / MEDIUM / LOW or equivalent)
- Description of the flagged issue
- Which reviewer(s) flagged it (if from multi-pr-review)

### Step 2: Validate Each Issue

For every flagged issue, **read the actual source code** using the Read tool. Check:

1. **Does the code actually have this problem?** — Read the file and surrounding context. Many review tools flag issues based on partial diff context and miss surrounding code that already handles the concern.
2. **Is the concern relevant to this codebase?** — Check if the flagged pattern is intentional, matches project conventions, or is handled elsewhere.
3. **Is the suggested fix correct?** — Sometimes the issue is real but the suggestion is wrong or unnecessary.
4. **Is this a style/preference issue disguised as a bug?** — Filter out subjective suggestions that were miscategorized as real problems.

For each issue, classify as:

- **VALID** — The issue is real and should be addressed. Keep its original severity.
- **INVALID** — False positive. The code is correct, the concern is already handled, or the issue is based on a misunderstanding of the code.

### Step 3: Output the Validated Report

Output a single consolidated report with all issues, ordered as:

```
## Validated Review Results

**Original issues:** [total count]
**Valid issues:** [count]
**Invalid/filtered:** [count]

---

### INVALID (Filtered Out)
For each filtered issue:
- ~~[original severity]~~ **file:line** — [brief description]
  **Reason dismissed:** [why this is not a valid issue — cite the code evidence]

---

### CRITICAL
- **file:line** — [description + suggested fix]
  **Validated by:** [what you checked to confirm this is real]

### HIGH
- **file:line** — [description + suggested fix]
  **Validated by:** [what you checked to confirm this is real]

### MEDIUM
- **file:line** — [description + suggested fix]
  **Validated by:** [what you checked to confirm this is real]

### LOW
- **file:line** — [description + suggested fix]
  **Validated by:** [what you checked to confirm this is real]

---

### Recommendations
[Overall assessment post-validation: merge-ready, needs-fixes, or needs-rework]
[Specific action items for remaining valid issues]
```

## Rules

- **Read before judging.** Never dismiss an issue without reading the actual code. Never confirm an issue without reading the actual code.
- **Be skeptical but fair.** The goal is to filter noise, not rubber-stamp everything as fine. If an issue is real, keep it.
- **Preserve information.** Every original issue must appear in the output — either in INVALID or in its severity section. Nothing gets silently dropped.
- **Explain dismissals.** Each INVALID entry must have a concrete reason with evidence from the code (e.g., "line 42 already checks for null before this call").
- **Don't add new issues.** This is a validation pass, not a new review. If you spot something new while reading, mention it briefly at the end under a "Notes" section but don't mix it into the validated results.
