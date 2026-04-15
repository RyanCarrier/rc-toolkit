---
description: Draft and open a new GitHub issue in the current repo
model: opus
argument-hint: [short description]
allowed-tools: Bash(gh issue create:*), Bash(gh issue view:*), Bash(gh repo view:*), Bash(gh label list:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git diff:*), Read, Write, Grep, Glob, AskUserQuestion
---

# Create GitHub Issue

Draft a new GitHub issue for the current repository, confirm with the user, then file it via `gh`.

## Seed description

`$ARGUMENTS`

## Current State

**Repository:**
!`gh repo view --json nameWithOwner,defaultBranchRef,url`

**Current branch:**
!`git rev-parse --abbrev-ref HEAD`

**Recent commits:**
!`git log --oneline -5`

**Available labels:**
!`gh label list --limit 50`

## Instructions

Work through these steps **sequentially** — each step builds on the previous one. Do not parallelize.

1. **Establish the seed.** If `$ARGUMENTS` above is empty, use `AskUserQuestion` to collect a one-line summary and any reproduction details before going further. If it is present, treat it as the starting point for the draft.

2. **Ground the issue in real code.** When the seed references behavior in this repo, use `Read`, `Grep`, and `Glob` to find the relevant files, symbols, and line numbers. Include these in the draft so the issue is actionable — do not invent file paths.

3. **Draft the issue.** Produce:
   - **Title:** under 70 characters, imperative mood, no trailing punctuation.
   - **Body (markdown):** sections in this order:
     - `## Summary` — one short paragraph describing the problem or request.
     - `## Context` — what you observed in the code / recent commits / CI, with file paths and line numbers where applicable.
     - `## Proposed outcome` — acceptance criteria as a bulleted checklist.
     - `## Notes` *(optional)* — anything the reporter should know (related issues, workarounds, out-of-scope items).

4. **Show the draft and confirm.** Print the full title and body back to the user, then use `AskUserQuestion` to:
   - Confirm the issue should be created as drafted (or request edits).
   - Pick zero or more labels from the **Available labels** list above. Do not invent new labels.
   - Ask whether to self-assign (`--assignee @me`). Default is no.

5. **Write the body to a temp file.** Only after explicit confirmation, use the `Write` tool to write the approved markdown body to `/tmp/rc-create-issue-body.md`. Do not use `cat` heredocs or nested command substitutions — the permission allowlist deliberately does not include `cat`, and `--body-file` keeps the command simple.

6. **Create the issue.** Run the command as a single `gh issue create` invocation (no pipes, no `$()`, no `&&` chains):

   ```bash
   gh issue create --title "<approved title>" --body-file /tmp/rc-create-issue-body.md [--label "<label>"]... [--assignee @me]
   ```

7. **Report the result.** Print the issue URL returned by `gh issue create` so the user can click through to it. The temp file at `/tmp/rc-create-issue-body.md` can be left in place — it will be overwritten on the next run.

## Scope

This command **only** drafts and creates an issue. Do not edit files, create branches, push code, or open PRs — those belong to other commands in this toolkit.
