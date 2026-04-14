---
description: Squash-merge current PR and delete branch (worktree-safe)
model: sonnet
context: none
allowed-tools: Bash(gh pr:*), Bash(git rev-parse:*), Bash(git worktree:*), Bash(git status:*), Bash(git log:*), Bash(pwd:*), Bash(bash:*)
---

# Squash Merge PR

Squash-merge the current branch's PR and clean up. Handles both worktree and normal working tree contexts.

## Current State

**Branch:** !`git branch --show-current`

## Instructions

### Step 1: Detect worktree status

Run these two commands and compare output:

```bash
git rev-parse --git-dir
git rev-parse --git-common-dir
```

If they differ, you are inside a worktree. Remember this — it changes the workflow below.

### Step 2: Gather PR details

Fetch PR info while still in the current working directory:

```bash
gh pr view --json number,title,state,reviewDecision,mergeStateStatus,headRefName,baseRefName,isDraft,url,commits,statusCheckRollup
```

Save the PR number, headRefName, baseRefName, and url — you will need them after changing directories.

**Abort if any of these are true:**
- No PR exists for this branch
- `state` is not `OPEN` (already merged or closed)
- `isDraft` is true

**Warn but continue if:**
- `reviewDecision` is not `APPROVED`
- `statusCheckRollup` has failing or pending checks
- `mergeStateStatus` is not `CLEAN`

Report all warnings clearly before proceeding.

### Step 3: Check for uncommitted or unpushed changes

```bash
git status --porcelain
git log origin/<baseRefName>..HEAD --oneline 2>/dev/null || git log @{u}..HEAD --oneline
```

If either command produces output, **abort** and report what would be lost. All changes must be committed and pushed before merging.

### Step 4: Show merge summary

```
PR: #<number> — <title>
Branch: <headRefName> -> <baseRefName>
Commits: <count> (will be squashed)
Review: <reviewDecision>
CI: <pass/fail/pending summary>
Merge status: <mergeStateStatus>
```

### Step 5: Execute merge via script

The bundled script handles worktree removal, squash merge, branch deletion, and pulling — all in one call.

**If in a worktree**, first get the main worktree path and current worktree path:

```bash
git worktree list --porcelain
```

The first `worktree <path>` line is the main worktree. Get the current path with `pwd`.

Then invoke the script with 5 arguments:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/squash-merge.sh" <number> <headRefName> <baseRefName> <main_worktree_path> <current_worktree_path>
```

**If NOT in a worktree**, invoke the script with 3 arguments:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/squash-merge.sh" <number> <headRefName> <baseRefName>
```

### Step 6: Report results

Show:
- Merge result (success/failure)
- Remote branch deleted
- Local branch deleted
- Worktree removed (if applicable)
- Local base branch updated
- PR URL for verification on GitHub

Do not use any tools besides the ones listed in allowed-tools. Do not read or modify any files.
