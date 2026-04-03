---
description: Fetch latest Copilot PR review, evaluate issue importance, and prepare to address them
model: opus
allowed-tools: Bash(gh pr:*), Bash(gh api:*), Bash(git rev-parse:*), Read
---

# Handle Copilot PR Review

Fetch the most recent GitHub Copilot review on the current PR, evaluate each issue by importance, and prepare to address them.

## Current State

**Current branch:**
!`git rev-parse --abbrev-ref HEAD`

## Instructions

1. **Fetch the PR number** for the current branch using `gh pr view --json number`

2. **Get Copilot's most recent review** using the GitHub API:

   First, get the most recent copilot review ID and body (sorted by submitted_at, take last):

   ```
   gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews --jq '[.[] | select(.user.login | contains("copilot"))] | sort_by(.submitted_at) | last | {id, body, submitted_at}'
   ```

   Then use that review ID to get only the comments from that specific review:

   ```
   gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews/{review_id}/comments --jq '.[] | {path, position, body}'
   ```

   Note: The review body contains the overview/summary, while the review comments contain inline code feedback.

3. **For each issue found**, evaluate and categorize:

   **Critical** - Must fix before merge:

   - Bugs that will cause runtime errors
   - Security vulnerabilities
   - Data loss risks

   **Important** - Should fix:

   - Logic errors that could cause incorrect behavior
   - Missing error handling for likely scenarios
   - Performance issues in hot paths

   **Minor** - Nice to have:

   - Code style suggestions
   - Minor optimizations
   - Documentation improvements

   **Ignore** - Not applicable:

   - False positives
   - Already addressed
   - Disagreements on style preference

4. **Output a prioritized action plan**:

   - List issues by priority (Critical > Important > Minor)
   - For each issue: file path, line, brief description, and suggested fix
   - Skip issues categorized as "Ignore" but mention them briefly

5. **Read the relevant files** to understand the context around each issue

6. **Prepare to implement fixes** - summarize what changes need to be made

Keep the evaluation practical. Focus on issues that matter for code correctness and maintainability.
