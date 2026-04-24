---
name: auto-branch
description: This skill should be used when the user asks to "auto branch", "auto-branch", "work on this autonomously", "handle this issue end to end", "implement this and create a PR", or wants fully autonomous development on a feature branch including implementation, testing, PR creation, review, and CI monitoring. Assumes the agent is already in a worktree/feature branch.
---

# Auto-Branch: Autonomous Feature Development

End-to-end autonomous development workflow for feature branches. Takes a task description or issue number, implements the solution, creates a PR, runs comprehensive reviews, and monitors CI — all with minimal user intervention.

**Assumption:** The agent is already checked out in the target feature branch or worktree. This skill does NOT create branches.

## Workflow

### Phase 1: Clarify Requirements

Before starting any work, gather enough context to proceed autonomously.

1. Read the task input — this may be a GitHub issue number (e.g. `#42`) or a freeform task description
2. If an issue number is provided, fetch it: `gh issue view <number> --json title,body,labels,comments`
3. Use `AskUserQuestion` to ask any clarifying questions about scope, constraints, or preferences — batch questions into a single prompt to minimize interruptions
4. After receiving answers, do NOT ask further questions — proceed autonomously from this point forward

### Phase 2: Diagnose and Investigate

Understand the codebase context relevant to the task.

1. Explore the repository structure — identify key files, patterns, and conventions
2. If fixing a bug, reproduce and diagnose the root cause
3. If adding a feature, identify where it fits in the architecture
4. Read CLAUDE.md, contributing guides, and any relevant documentation
5. Check existing tests to understand testing patterns and conventions

### Phase 3: Plan

Create a concrete implementation plan.

1. Outline the implementation approach before writing code
2. Identify specific files to create or modify
3. Define the test strategy
4. Consider edge cases and error handling
5. Begin implementation

### Phase 4: Implement

Execute the plan using subagents or direct implementation as appropriate.

1. Implement the changes following existing codebase conventions
2. Write tests alongside the implementation — match existing test patterns
3. For large changes, use subagents to parallelize independent work streams
4. Commit incrementally with descriptive messages as logical units complete

### Phase 5: Pre-commit Validation

Run all available validation before creating the PR.

1. Run the project's lint/format tools (check package.json scripts, Makefile, or similar)
2. Run the test suite: `npm test`, `cargo test`, `pytest`, or whatever the project uses
3. Fix any failures — iterate until all checks pass locally
4. Stage and commit all remaining changes

### Phase 6: Create PR

Push the branch and open a pull request.

1. Push the branch: `git push -u origin $(git branch --show-current)`
2. Create the PR with `gh pr create` — write a clear title and description summarizing the changes, test plan, and any relevant context
3. Note the PR number for subsequent steps

### Phase 7: Comprehensive Review (2 rounds)

Run the multi-pr-review agent to get multi-perspective feedback.

**Round 1:**
1. Invoke the multi-pr-review agent (rc-toolkit agent)
2. Analyze the consolidated findings
3. Implement fixes for all CRITICAL and HIGH issues
4. Implement fixes for MEDIUM issues where the fix is clear and low-risk
5. Commit and push fixes

**Round 2:**
1. Run multi-pr-review again on the updated code
2. Implement any remaining fixes
3. Commit and push

**After 2 rounds:** Present the user with a status update:
- Summary of issues found and fixed across both rounds
- Any remaining issues and their severity
- Recommendation: whether more review rounds are needed or if a targeted review of specific areas would be more productive
- Ask the user whether to continue with additional reviews or proceed to CI monitoring

### Phase 8: CI Monitoring

Wait for CI to complete and handle failures.

1. Monitor CI status: `gh pr checks $(gh pr view --json number -q .number) --watch`
2. If CI passes, proceed to the summary
3. If CI fails:
   a. Fetch failure details — first get the run ID (retry up to 3 times with 10s waits if empty, since CI may not have registered yet): `gh run list --branch $(git branch --show-current) --status failure --limit 1 --json databaseId -q '.[0].databaseId'`, then view the logs using the returned ID as a separate command: `gh run view <run-id> --log-failed`
   b. Diagnose and fix the failures
   c. Commit, push, and wait for CI again
   d. Repeat until CI passes (up to 3 attempts)
4. If CI still fails after 3 attempts, report the situation to the user with diagnostics

### Phase 9: Final Summary

Present a complete summary for the user to review and merge.

```
## Auto-Branch Summary

**Task:** [original task description]
**Branch:** [branch name]
**PR:** [PR URL]
**CI Status:** [passing/failing]

### Changes Made
- [file-by-file summary of changes]

### Tests Added/Modified
- [test summary]

### Review Results
- **Rounds completed:** [N]
- **Issues found:** [total across all rounds]
- **Issues fixed:** [total fixed]
- **Remaining:** [any unresolved items and why]

### CI Results
- **Attempts:** [N]
- **Final status:** [pass/fail]
- [If failed: what's still broken and recommended next steps]

### Ready to Merge?
[Assessment: yes/no with reasoning]
```

## Key Principles

- **Ask once, then execute** — all user interaction happens in Phase 1
- **Fix forward** — when reviews or CI find issues, fix them rather than reporting back
- **Incremental commits** — commit logical units of work, not one giant commit
- **Match conventions** — follow the existing codebase style, test patterns, and tooling
- **Subagents for parallelism** — use the Agent tool to parallelize independent work where it makes sense
- **Transparency in summary** — the final summary should give the user full confidence to review and merge

## Additional Resources

### Reference Files

For detailed workflow guidance, consult:
- **`references/ci-troubleshooting.md`** — Common CI failure patterns and fixes
