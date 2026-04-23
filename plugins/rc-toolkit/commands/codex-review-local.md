---
description: Run a Codex code review on uncommitted local changes
model: haiku
context: none
allowed-tools: Bash(mkdir:*), Bash(codex:*), Bash(git status:*), Read
---

# Codex Review (Local)

Runs OpenAI Codex's built-in code review on uncommitted local changes (staged, unstaged, and untracked).

**Prerequisite:** `codex` CLI installed (`npm install -g @openai/codex`) and authenticated (`codex login`).

## Current State

**Changed files:**
!`git status --short`

## Instructions

**CRITICAL:** Your ONLY job is to run the Codex review command below and output the result. Do NOT perform your own review. Do NOT skip the command.

### Step 1: Check for Changes

If `git status --short` above shows no changes, tell the user there are no local changes to review and stop.

### Step 2: Run Codex Review

Run these exact commands using the Bash tool with a 300s timeout:

```bash
mkdir -p tmp && codex review --uncommitted 2>tmp/codex_review_local_error.txt
```

### Step 3: Output the Result

Output the Codex review text directly to the user. Do not summarize or modify it.

If the command produces no output or fails, read `tmp/codex_review_local_error.txt` and report the error to the user. Common issues:

- `codex` CLI not installed (`npm install -g @openai/codex`)
- Not authenticated (`codex login`)
- `OPENAI_API_KEY` not set
- Not in a git repository
