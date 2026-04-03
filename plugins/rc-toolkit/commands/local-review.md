---
description: Full code review of all unpushed local changes - unstaged, staged, and committed
model: opus
context: none
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git log:*), Bash(git branch:*), Read
---

# Local Review

Perform a thorough code review of all local changes that haven't been pushed yet. This includes unstaged changes, staged changes, and commits not yet on the remote.

## Current State

**Branch:**
!`git branch --show-current`

**Changed files (working tree):**
!`git status --short`

**Unpushed commits:**
!`git log --oneline @{upstream}..HEAD 2>/dev/null || echo "No upstream tracking branch"`

## Instructions

### Step 1: Get the Full Diff

Get the combined diff of everything local vs what's on the remote:

```bash
git diff origin/$(git branch --show-current) 2>/dev/null || git diff origin/main...HEAD
```

This captures:
- Unstaged working tree changes
- Staged changes
- Committed-but-not-pushed changes

If the diff is empty, tell the user there are no unpushed changes to review and stop.

### Step 2: Review the Changes

Act as a senior engineer performing a thorough code review. Analyze the diff and identify:

1. **Bugs & Logic Errors** - Incorrect conditions, off-by-one errors, null/undefined handling, race conditions, edge cases
2. **Security Concerns** - Injection vulnerabilities, exposed secrets, unsafe operations, auth issues
3. **Performance Issues** - Unnecessary allocations, N+1 queries, missing caching opportunities, hot path inefficiencies
4. **Error Handling** - Uncaught exceptions, missing null checks, silent failures, inadequate fallbacks
5. **Architectural Issues** - Coupling, missing abstractions, API design problems, inconsistent patterns
6. **Unintended Side Effects** - Changes that might break other parts of the codebase

### Step 3: Read Files for Context

For any issue that needs more context to evaluate, use the Read tool to examine the surrounding code. Don't flag issues you're uncertain about without checking context first.

### Step 4: Output

For each issue found:

- **File path and line(s)**
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Description** of the issue with reasoning
- **Suggested fix** with concrete code if applicable

Classify severity as:
- **CRITICAL**: Security vulnerabilities, data loss, system-breaking bugs
- **HIGH**: Bugs that will cause incorrect behavior, resource leaks, major architectural issues
- **MEDIUM**: Missing validation, complex logic that could be simplified, potential edge cases
- **LOW**: Minor refactoring opportunities, documentation gaps

If no issues found, state the changes look clean and ready to push.

Do NOT comment on:
- Style or formatting preferences
- Things that are correct and fine as-is
- Hypothetical issues that require unlikely conditions
