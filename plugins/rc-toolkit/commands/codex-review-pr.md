---
description: Run a Codex code review on the current branch against main
model: haiku
context: none
allowed-tools: Bash(mkdir:*), Bash(codex:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git log:*), Read
---

# Codex Review (PR)

Runs OpenAI Codex's built-in code review on the current branch compared to the base branch (main/master).

**Prerequisite:** `codex` CLI installed (`npm install -g @openai/codex`) and authenticated (`codex login`).

## Current State

**Current branch:**
!`git branch --show-current`

**Unpushed commits:**
!`git log --oneline @{upstream}..HEAD 2>/dev/null || echo "No upstream tracking branch"`

## Instructions

**CRITICAL:** Your ONLY job is to detect the base branch, run the Codex review command below, and output the result. Do NOT perform your own review. Do NOT skip the command.

### Step 1: Detect Base Branch

Determine the base branch by checking which exists:

```bash
git rev-parse --verify origin/main 2>/dev/null && echo "main" || git rev-parse --verify origin/master 2>/dev/null && echo "master"
```

Use whichever branch exists (`main` preferred over `master`). If neither exists, tell the user and stop.

If the current branch IS the base branch, tell the user to switch to a feature branch first and stop.

### Step 2: Run Codex Review

Run this command using the Bash tool with a 300s timeout, substituting the detected base branch:

```bash
mkdir -p tmp && codex review --base <BASE_BRANCH> 2>tmp/codex_review_pr_error.txt
```

For example: `mkdir -p tmp && codex review --base main 2>tmp/codex_review_pr_error.txt`

### Step 3: Output the Result

Output the Codex review text directly to the user. Do not summarize or modify it.

If the command produces no output or fails, read `tmp/codex_review_pr_error.txt` and report the error to the user. Common issues:

- `codex` CLI not installed (`npm install -g @openai/codex`)
- Not authenticated (`codex login`)
- `OPENAI_API_KEY` not set
- Not in a git repository
- No commits on branch compared to base
