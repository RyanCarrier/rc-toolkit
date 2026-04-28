---
description: Fix review issues, run pre-commit checks, commit, push, and re-run multi-pr-review
argument-hint: [issue descriptions or numbers to fix — omit to fix recommended issues]
model: opus
---

# Fix and Re-Review

Fix issues flagged in a prior review, then commit, push, and re-run the full multi-PR review.

## Prerequisites

This command expects review results to already be present in the conversation (from `/multi-pr-review`, `/local-review`, `/quick-review`, `/validate-review`, etc.). If no review results are present, tell the user to run a review first and stop.

## Arguments

**Specified issues:** `$ARGUMENTS`

- If arguments are provided, fix only the issues described in the arguments.
- If no arguments are provided, fix all issues listed under the **Recommendations** or **action items** section of the most recent review output. If no clear recommendations exist, fix all CRITICAL and HIGH severity issues.

## Instructions

### Step 1: Identify Issues to Fix

Parse the review results from the conversation. Based on arguments:

- **With arguments:** Match `$ARGUMENTS` against the flagged issues (by description, file, or number in the list). Fix only those.
- **Without arguments:** Collect all issues from the Recommendations/action items section. If none, collect all CRITICAL and HIGH severity issues.

List the issues to be fixed before starting work. If no actionable issues are found, report that and stop.

### Step 2: Fix the Issues

For each issue, read the relevant source code, understand the context, and apply the fix. Follow existing code conventions. Do not refactor surrounding code or add unrelated changes.

### Step 3: Run Pre-Commit Checks

After all fixes are applied, run pre-commit checks to catch lint, format, or type errors.

**First, check for a pre-commit skill or command in the project.** Search available skills and commands (e.g., look for skills matching "pre-commit", "lint", "check", or "format" in the plugin/skill listings). If one exists, invoke it — it knows the project's specific checks and is always preferred.

**Only if no pre-commit skill/command exists**, fall back to inferring from project tooling. Detect the project's tooling and run the appropriate commands. Look for:

- `npm run lint` / `npm run check` / `npm run typecheck` / `npm run format`
- `make lint` / `make check` / `make fmt`
- `cargo fmt` / `cargo check` / `cargo clippy`
- `go fmt` / `go vet` / `golangci-lint run`
- `ruff check` / `ruff format` / `mypy`

Fix any issues surfaced before proceeding.

### Step 4: Commit and Push

Stage only the files changed by the fixes. Commit with a message summarizing what was fixed (reference the review). Push to the current branch.

```bash
git add <changed-files>
git commit -m "<descriptive message>"
git push
```

### Step 5: Re-Run Multi-PR Review

Invoke the multi-pr-review to validate the fixes and check for remaining issues:

```
Skill(skill="rc-toolkit:multi-pr-review")
```
