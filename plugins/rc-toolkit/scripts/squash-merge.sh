#!/usr/bin/env bash
set -euo pipefail

# Usage: squash-merge.sh <pr_number> <branch_name> <base_branch> [<main_worktree_path> <current_worktree_path>]
#
# 3 args: normal flow (merge + pull)
# 5 args: worktree flow (remove worktree, merge + pull)

PR_NUMBER="$1"
BRANCH_NAME="$2"
BASE_BRANCH="$3"
MAIN_WORKTREE="${4:-}"
CURRENT_WORKTREE="${5:-}"

if [[ -n "$MAIN_WORKTREE" && -n "$CURRENT_WORKTREE" ]]; then
  echo "Removing worktree at $CURRENT_WORKTREE..."
  cd "$MAIN_WORKTREE"
  git worktree remove "$CURRENT_WORKTREE"
  echo "Worktree removed."
fi

echo "Squash-merging PR #$PR_NUMBER..."
gh pr merge "$PR_NUMBER" --squash --delete-branch
echo "PR #$PR_NUMBER merged and branch $BRANCH_NAME deleted."

echo "Pulling latest $BASE_BRANCH..."
git pull origin "$BASE_BRANCH"
echo "Local $BASE_BRANCH updated."
