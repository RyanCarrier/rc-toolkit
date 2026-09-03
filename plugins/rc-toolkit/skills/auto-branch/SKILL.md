---
name: auto-branch
description: This skill should be used when the user asks to "auto branch", "auto-branch", "work on this autonomously", "handle this issue end to end", "implement this and create a PR", or wants fully autonomous development on a feature branch including implementation, testing, PR creation, review, CI monitoring, and in-app verification posted to the PR. Assumes the agent is already in a worktree/feature branch.
---

# Auto-Branch: Autonomous Feature Development

End-to-end autonomous development workflow for feature branches. Takes a task description or issue number, implements the solution, creates a PR, runs comprehensive reviews, monitors CI, and verifies the change in the running app with evidence posted to the PR — all with minimal user intervention.

**Assumption:** The agent is already checked out in the target feature branch or worktree. This skill does NOT create branches.

## Workflow

### Phase 1: Clarify Requirements

Before starting any work, gather enough context to proceed autonomously.

1. Read the task input — this may be a GitHub issue number (e.g. `#42`) or a freeform task description
2. If an issue number is provided, fetch it: `gh issue view <number> --json title,body,labels,comments`
3. Ask any clarifying questions about scope, constraints, or preferences using the host's user-input mechanism — batch questions into a single prompt to minimize interruptions
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
3. For each significant decision, record a brief justification — why this approach over the alternatives — and its blast radius: callers, dependents, and tests affected, verified with actual searches rather than assumption
4. Define the test strategy
5. Consider edge cases and error handling
6. Begin implementation

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
2. Create the PR with `gh pr create` — write a clear title and description summarizing the changes, the key decisions with their justifications and blast radius from Phase 3, the test plan, and any relevant context
3. Note the PR number for subsequent steps

### Phase 7: Comprehensive Review

Delegate the review-and-fix loop to the `rc-toolkit:review-loop` skill. It runs one full review, then plan → fix → delta re-review cycles until no CRITICAL/HIGH fixable issues remain, the count stops falling, or its iteration/time budget is exhausted. Findings that need a product decision or fall outside the PR's scope are collected, not fixed.

1. Invoke the loop **through a subagent**, so control returns here for Phase 8. In Claude Code, call:

   ```
   Agent(
     description="Review loop",
     prompt="Run the full review-and-fix loop on the current PR. Invoke Skill(skill='rc-toolkit:review-loop') and let it run to completion. Run in non-interactive mode: do NOT prompt the user at any point — write the report and stop. Return: total iterations completed, issues found, issues fixed, every remaining issue, every pending decision with its brief, and every parked (out-of-scope) item with its reason."
   )
   ```

   In Codex, load the `developer-workflows` skill and run the `review-loop` workflow it maps to, delegating it the same way.

   **Do not call `Skill(skill="rc-toolkit:review-loop")` directly here.** Skill() loads the loop's instructions into the current turn, and `review-loop` is written as a terminal controller that ends with "stop" — Phases 8 through 10 would never run. This is the same constraint `review-loop` states for itself: its orchestrator spawns subagents rather than calling `Skill()`, because Skill() takes over the turn.

2. Let the loop run to completion. It handles its own severity counting, fix subagents, re-review, and iteration budget. Do NOT run `multi-pr-review` manually here — `review-loop` owns this phase.
3. Record the subagent's returned summary (iterations, issues found/fixed, anything left unfixed and why, pending decisions, parked items) for the Phase 10 summary. Because the loop runs non-interactively here, decisions and parked items come back unanswered in the report rather than as prompts — carry them into Phase 10 so the user can answer them and decide whether to keep going.
4. Proceed to Phase 8.

### Phase 8: CI Monitoring

Delegate CI monitoring to the `rc-toolkit:ci-loop` skill, which polls the latest run, classifies failures as fixable vs external, fixes and pushes, and retries until green or blocked.

1. Invoke the loop **through a subagent**, so control returns here for Phase 9. In Claude Code, call:

   ```
   Agent(
     description="CI loop",
     prompt="Monitor and repair CI on the current PR. Invoke Skill(skill='rc-toolkit:ci-loop') and let it run to completion. Return: number of attempts made, final CI status, and — if CI is not green — what is still failing and what external action it needs."
   )
   ```

   In Codex, load the `developer-workflows` skill and run the `ci-loop` workflow it maps to, delegating it the same way.

   **Do not call `Skill(skill="rc-toolkit:ci-loop")` directly here** — same reason as Phase 7. `ci-loop` ends every path with "report and stop", which would end the turn before Phase 9 runs.

2. Let it run to completion. It owns this phase: polling, failure classification, pre-commit checks, commits, pushes, iteration limits, and stall detection. Do NOT reimplement CI polling or fetch failure logs manually here.
3. Record the subagent's returned status and diagnostics for the Phase 10 summary.

### Phase 9: Verify and Demonstrate

Prove the finished change works in the running app and post the evidence on the PR, so a reviewer can see it working without checking out the branch. This runs on the branch's final state — after review fixes and CI fixes have landed — so it shows what will actually merge.

1. Decide whether it applies. It applies when the change alters something a user can observe: a web page or component, a TUI or desktop screen, CLI output or help text, an API response, a rendered document or diagram. It does not apply to internal refactors, CI and tooling config, dependency bumps, or test-only changes. When it does not apply, record `Verification: not applicable — <reason>` for Phase 10 and skip to it.
2. Launch and drive the app **through a subagent**, so launch noise stays out of this context and control returns here. In Claude Code, call:

   ```
   Agent(
     description="Verify feature",
     prompt="Launch and drive this project's app at the current branch HEAD and verify <the behaviour the task changed>. Invoke Skill(skill='run') and follow it — it picks the launch recipe by project type and reuses any project run-* skill. Exercise the changed behaviour, not just the entrypoint. If the surface is visual, save a screenshot PNG to /tmp/rc-auto-branch/verify-1.png and look at it — a blank or error frame is a failed launch, not evidence. If the surface is text (CLI, API), capture the relevant output. Shut down anything you started. Do NOT prompt the user. Return: what was launched and how, what was exercised, what was observed, the path of any capture, and any launch failure."
   )
   ```

   In Codex, follow the same recipe by hand: a dev server plus a Playwright script (`npx playwright screenshot --full-page <url> <file>`) for web, tmux `send-keys`/`capture-pane` for a TUI, direct invocation for a CLI.

3. Check the evidence before using it. `gh` accepts png, jpg, jpeg, gif, webp, and svg images up to 10 MB and mp4, mov, and webm videos up to 100 MB; the extension decides the type. A failed capture, an unsupported file, or a blank frame means the comment goes out text-only with a note saying why.
4. Post a `## Verification` comment on the PR with `gh pr comment <number> --body-file <file> --attach '<capture>#<alt text>'`. The body states what was exercised, what was observed, and the commit SHA verified; text evidence goes in a fenced code block. Reference the image in the body with the identical path passed to `--attach`, for example `![Settings page after the change](/tmp/rc-auto-branch/verify-1.png)`, so `gh` rewrites it in place — an unreferenced attachment is appended to the end instead. Comment rather than edit the PR body: a comment is additive and tied to the final state, while the Phase 6 description stays intact. If `gh` rejects the attachment (attachments need GitHub.com or Enterprise Cloud; GHES is unsupported), post the text-only comment and note the reason.
5. Record for Phase 10: what was exercised, what was observed, and the comment URL — or the reason nothing was posted.

Do not fabricate evidence. If the app cannot be launched or the behaviour cannot be reached, say so in the summary instead of posting a comment.

### Phase 10: Final Summary

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

### Verification
- **Exercised:** [what was launched and driven, or "not applicable — reason"]
- **Observed:** [what the app showed]
- **Evidence:** [PR comment URL with the screenshot or output, or why none was posted]

### Ready to Merge?
[Assessment: yes/no with reasoning]
```

## Key Principles

- **Ask once, then execute** — all user interaction happens in Phase 1
- **Fix forward** — when reviews or CI find issues, fix them rather than reporting back
- **Incremental commits** — commit logical units of work, not one giant commit
- **Match conventions** — follow the existing codebase style, test patterns, and tooling
- **Subagents for parallelism and for control** — use the Agent tool to parallelize independent work, and to run any delegated workflow that ends by stopping (Phases 7 and 8) or that launches the app (Phase 9), so control returns here for the next phase
- **Transparency in summary** — the final summary should give the user full confidence to review and merge
- **Evidence on the PR** — when the change is observable, verify it in the running app and post the proof (Phase 9), so a reviewer sees it working before reading the diff

## Additional Resources

### Reference Files

For detailed workflow guidance, consult:
- **`references/ci-troubleshooting.md`** — Common CI failure patterns and fixes
