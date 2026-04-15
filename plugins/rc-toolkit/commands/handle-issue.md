---
description: Fetch a GitHub issue and enter plan mode to design the fix
model: opus
argument-hint: <issue-number>
allowed-tools: Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh repo view:*), Bash(git rev-parse:*), Bash(git branch:*), Read, Grep, Glob, EnterPlanMode
---

# Handle GitHub Issue

Fetch the referenced GitHub issue, gather enough codebase context to understand it, then enter plan mode to design the fix before any code is written.

## Arguments

**Issue number:** `$ARGUMENTS`

## Current State

**Current branch:**
!`git rev-parse --abbrev-ref HEAD`

**Repository:**
!`gh repo view --json nameWithOwner,defaultBranchRef`

**Issue:**
!`gh issue view $ARGUMENTS --json number,title,state,labels,author,body,comments,assignees,url`

## Instructions

Work through these steps **sequentially** — do not parallelize; each step depends on what the previous step learned.

1. **Validate the issue payload.** Look at the `gh issue view` output in the context block. If it errored (empty `$ARGUMENTS`, non-numeric, or issue not found), stop and ask the user to re-run with a valid issue number (e.g. `/rc-toolkit:handle-issue 123`). Do not continue to the next step.

2. **Read the issue carefully.** Parse the title, body, labels, and all comments. Note any reproduction steps, expected behavior, affected files, and constraints the reporter mentioned.

3. **Ground the issue in the codebase.** Use `Read`, `Grep`, and `Glob` to locate the files, functions, and call sites the issue refers to. If the issue is vague, search for keywords from the title and body. Do not make assumptions about code you have not read.

4. **Check branch state.** Run `git branch --list` if needed. If a branch clearly related to this issue already exists (e.g. `issue-<n>`, `fix/<slug>`), note it — the user may want to continue on that branch instead of starting fresh.

5. **Enter plan mode.** Only after the previous steps are complete, call the `EnterPlanMode` tool to hand off to the standard planning workflow. Do **not** edit any files in this command — planning only.

6. **Once in plan mode**, follow the normal Phase 1–5 plan workflow (explore → design → review → final plan → `ExitPlanMode`). The final plan should explicitly reference the issue number and URL from the context block above so the resulting plan file is traceable back to the issue.
