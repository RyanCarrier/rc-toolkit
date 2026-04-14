#!/usr/bin/env bash
set -euo pipefail

# Usage: squash-merge.sh <pr_number> <branch_name> <base_branch> [<main_worktree_path> <current_worktree_path>]
#
# 3 args: normal flow (merge + pull)
# 5 args: worktree flow (remove worktree, merge + pull)

if [[ $# -ne 3 && $# -ne 5 ]]; then
  echo "Error: Expected 3 or 5 arguments, got $#"
  echo "Usage: squash-merge.sh <pr_number> <branch_name> <base_branch> [<main_worktree_path> <current_worktree_path>]"
  exit 1
fi

PR_NUMBER="$1"
BRANCH_NAME="$2"
BASE_BRANCH="$3"
MAIN_WORKTREE="${4:-}"
CURRENT_WORKTREE="${5:-}"

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: PR number must be a positive integer, got '$PR_NUMBER'"
  exit 1
fi

if [[ -z "$BRANCH_NAME" ]]; then
  echo "Error: Branch name cannot be empty"
  exit 1
fi

if [[ -z "$BASE_BRANCH" ]]; then
  echo "Error: Base branch cannot be empty"
  exit 1
fi

if [[ -n "$MAIN_WORKTREE" && -n "$CURRENT_WORKTREE" ]]; then
  if [[ ! -d "$MAIN_WORKTREE" ]]; then
    echo "Error: Main worktree path does not exist: $MAIN_WORKTREE"
    exit 1
  fi
  if [[ ! -d "$CURRENT_WORKTREE" ]]; then
    echo "Error: Current worktree path does not exist: $CURRENT_WORKTREE"
    exit 1
  fi

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
