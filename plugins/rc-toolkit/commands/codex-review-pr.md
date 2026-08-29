---
description: Run a Codex code review on the current branch against its base branch
model: haiku
context: none
allowed-tools: Bash(mkdir:*), Bash(codex:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git log:*), Bash(gh pr view:*), Read
argument-hint: [--base <ref>] [review instructions]
---

# Codex Review (PR)

Runs OpenAI Codex's built-in code review on the current branch compared to the PR's base branch (falling back to main/master when no PR exists), or against an explicit `--base <ref>`.

**Prerequisite:** `codex` CLI installed (`npm install -g @openai/codex`) and authenticated (`codex login`).

## Arguments

`$ARGUMENTS` may carry:

- `--base <ref>` — review the changes since this ref instead of the detected base branch. A commit SHA is valid: `review-loop` passes the pre-fix commit here so Codex reviews only the fix commits.
- Any remaining text is passed to Codex as custom review instructions (the reviewer brief).

## Current State

**Current branch:**
!`git branch --show-current`

**Unpushed commits:**
!`git log --oneline @{upstream}..HEAD 2>/dev/null || echo "No upstream tracking branch"`

## Instructions

**CRITICAL:** Your ONLY job is to determine the base ref, run the Codex review command below, and output the result. Do NOT perform your own review. Do NOT skip the command.

### Step 1: Determine the Base Ref

If `--base <ref>` was given, use it and skip detection.

Otherwise prefer the PR's **actual base branch** (so stacked PRs compare correctly); fall back to `main`/`master`:

```bash
gh pr view --json baseRefName -q .baseRefName 2>/dev/null || (git rev-parse --verify --quiet origin/main >/dev/null 2>&1 && echo main || (git rev-parse --verify --quiet origin/master >/dev/null 2>&1 && echo master))
```

If it prints nothing, tell the user no base branch could be determined and stop. If the current branch IS the base branch, tell the user to switch to a feature branch first and stop.

### Step 2: Run Codex Review

Run this with the Bash tool with a 300s timeout, substituting the base ref and the instructions (omit the trailing argument if none were given):

```bash
mkdir -p tmp && codex review --base <BASE_REF> "<REVIEW INSTRUCTIONS>" 2>tmp/codex_review_pr_error.txt
```

Examples:

```bash
mkdir -p tmp && codex review --base main 2>tmp/codex_review_pr_error.txt
mkdir -p tmp && codex review --base 3f2a9c1 "Flag only issues that affect correctness, security, or the PR's stated intent. Cite file:line. Do not report style." 2>tmp/codex_review_pr_error.txt
```

### Step 3: Output the Result

Output the Codex review text directly to the user. Do not summarize or modify it.

If the command produces no output or fails, read `tmp/codex_review_pr_error.txt` and report the error. Common issues:

- `codex` CLI not installed (`npm install -g @openai/codex`)
- Not authenticated (`codex login`)
- `OPENAI_API_KEY` not set
- Not in a git repository
- No commits on branch compared to the base ref
