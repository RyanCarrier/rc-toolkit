---
description: Brief code review of local changes (staged + unstaged) - senior engineer quick scan
model: opus
context: fork
allowed-tools: Bash(git diff:*), Bash(git status:*), Read
---

# Quick Code Review

Perform a brief code review of the local changes below. Act as a senior engineer doing a quick once-over before commit - not a comprehensive audit.

## Current State

**Changed files:**
!`git status --short`

**Full diff (staged + unstaged):**
!`git diff HEAD`

## Review Instructions

Scan the diff above and identify any **actual issues** that could cause problems:

1. **Bugs & Logic Errors** - Incorrect conditions, off-by-one errors, null/undefined handling, edge cases
2. **Unintended Side Effects** - Changes that might break other parts of the codebase
3. **Security Concerns** - Injection vulnerabilities, exposed secrets, unsafe operations
4. **Missing Error Handling** - Uncaught exceptions, missing null checks where needed
5. **Project Convention Violations** - Only if they could cause real problems (not style preferences)

## Output Format

If issues found:

- List each issue with file path and brief description
- Suggest a fix if straightforward

If no issues:

- Simply state the changes look good

**Keep it brief.** This is a quick sanity check, not a comprehensive review. Don't mention:

- Style preferences or formatting
- Minor improvements that aren't problems
- Things that are fine as-is
