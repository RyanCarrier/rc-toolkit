---
description: Squash-merge current PR and delete branch (worktree-safe)
model: sonnet
context: none
allowed-tools: Bash(gh pr:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git worktree:*), Bash(git status:*), Bash(git log:*), Bash(cd:*), Bash(pwd:*), Bash(git pull:*)
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

### Step 5: Worktree cleanup (worktree only)

**Skip this step if NOT in a worktree.** Jump to Step 6.

If in a worktree:

1. Get the main worktree path (the first entry from `git worktree list`):

   ```bash
   git worktree list --porcelain
   ```

   The first `worktree <path>` line is the main worktree.

2. Save the current worktree path:

   ```bash
   pwd
   ```

3. Change directory to the main worktree, then remove the current worktree:

   ```bash
   cd "<main-worktree-path>" && git worktree remove "<current-worktree-path>"
   ```

   You are now in the main worktree on the base branch. All subsequent commands run from here.

### Step 6: Squash merge and delete branch

Use the PR number captured in Step 2 (required since you may no longer be on the branch):

```bash
gh pr merge <number> --squash --delete-branch
```

`--delete-branch` is safe here because:
- In the worktree flow: the worktree was already removed and we're on the base branch in the main worktree, so the local branch checkout and deletion both succeed.
- In the normal flow: works as normal.

### Step 7: Update local base branch

Pull the latest changes to ensure the local base branch matches the merge result:

```bash
git pull origin <baseRefName>
```

### Step 8: Report results

Show:
- Merge result (success/failure)
- Remote branch deleted
- Local branch deleted
- Worktree removed (if applicable)
- Local base branch updated
- PR URL for verification on GitHub

Do not use any tools besides the ones listed in allowed-tools. Do not read or modify any files.
