---
name: developer-workflows
description: This skill should be used on hosts without native rc-toolkit slash commands (primarily Codex) when the user asks to "quick review", "review local changes", "run a multi PR review", "break down this review", "validate review findings", "plan review fixes", "review the fix plan", "fix and re-review", "run the review loop", "diagnose CI", "run the CI loop", "get the Copilot review", "handle the Copilot review", "review with Codex", "review with Antigravity", "create an issue", "handle issue 123", "commit and push", or "squash merge". In Claude Code the native rc-toolkit slash commands take precedence over this skill.
---

# Developer Workflows

Run the rc-toolkit developer workflows on hosts that have no native
`/rc-toolkit:*` slash commands — primarily Codex — while keeping the detailed
workflow definitions in one place.

## Check the Host First

Every workflow listed below is also registered as a native `/rc-toolkit:<name>`
command in Claude Code. In Claude Code, invoke that command directly and ignore
the translations in this skill.

This matters because the translations flatten `Skill()` and `Agent()` calls into
the current turn. Several workflows depend on those being real delegations:
`review-loop` and `multi-pr-review` collect results from subagents and continue
working afterwards, which a same-turn `Skill()` call cannot do. Applying the
translations in Claude Code breaks that isolation.

Apply the rest of this skill only when the host offers no native
`/rc-toolkit:*` command.

## Select the Workflow

Map the user's intent to a file under `../../commands/`:

| Intent | Workflow file |
|---|---|
| Brief local sanity check | `quick-review.md` |
| Thorough unpushed-change review | `local-review.md` |
| Multi-provider PR review | `multi-pr-review.md` |
| Sectioned PR review | `breakdown-review.md` |
| Validate reported findings | `validate-review.md` |
| Plan validated fixes | `plan-fixes.md` |
| Critique a fix plan | `adversarial-plan-review.md` |
| Fix findings and review again | `fix-rereview.md` |
| Iterate review through fixes | `review-loop.md` |
| Inspect the latest failed CI run | `get-ci-failures.md` |
| Wait, repair, and retry CI | `ci-loop.md` |
| Fetch and validate Copilot review | `get-copilot-review.md` |
| Fetch, validate, and fix Copilot review | `handle-copilot-review.md` |
| Run Codex review on local changes | `codex-review-local.md` |
| Run Codex review on a branch or PR | `codex-review-pr.md` |
| Run Antigravity PR review | `agy-review-pr.md` |
| Draft and create a GitHub issue | `create-issue.md` |
| Investigate an existing GitHub issue | `handle-issue.md` |
| Commit and push current changes | `commit-push.md` |
| Squash-merge the current PR | `squash-merge.md` |

Resolve the referenced file relative to this `SKILL.md`. Read the entire
selected workflow before acting. Read another workflow when the selected one
delegates to it. Do not load unrelated workflow files.

## Translate Host-Specific Syntax

Treat the command Markdown as procedural instructions, with these translations:

- Ignore command frontmatter fields such as `model`, `context`,
  `allowed-tools`, and `argument-hint`. Follow the active host's tool and
  permission policies.
- Execute each `!` backtick command at the point its output is required. The
  text is Claude command interpolation, not precomputed content in Codex.
- Treat `$ARGUMENTS` as the text following the workflow name in the user's
  request. Infer it from natural language when no literal slash command exists.
- Treat `Skill(skill="rc-toolkit:<name>")` as an instruction to read and run
  `../../commands/<name>.md` in the current task.
- Treat a `Skill(...)` reference to any other plugin — notably
  `pr-review-toolkit:review-pr` in `multi-pr-review.md` and
  `breakdown-review.md` — as a request for a reviewer that does not exist on
  this host. There is no matching file under `../../commands/`, so do not try to
  resolve it as one. Perform that review directly in the current session over
  the same scope, and label the output with the reviewer that actually ran so
  the consolidation step does not misattribute it. If no equivalent is
  available, skip that reviewer, state the omission in the output, and continue
  with the remaining reviewers rather than aborting the workflow.
- Treat an `Agent(...)` block as an instruction to delegate that bounded task
  to a subagent when subagents are available and allowed. Run it directly when
  delegation is unavailable, while preserving the requested isolation and
  output contract. When running one inline, a "stop" or "report and stop" at the
  end of the delegated workflow ends only that workflow — return to the calling
  workflow and continue from where it left off. Several workflows are written as
  terminal controllers (`review-loop`, `ci-loop`), so taking their stop literally
  would abandon the remaining phases of whatever invoked them.
- Treat `AskUserQuestion` as a normal concise question using the host's
  available user-input mechanism. Continue with safe work when the answer is
  useful but non-blocking.
- Treat `EnterPlanMode` and `ExitPlanMode` as requests to use the host's
  planning workflow. If the host cannot switch modes during a skill, investigate
  without editing and return a complete implementation plan.
- Resolve `${CLAUDE_PLUGIN_ROOT}` and `${PLUGIN_ROOT}` to the plugin root. From
  this skill, the plugin root is `../..`.
- Interpret references to `/rc-toolkit:<name>` as the corresponding workflow
  intent; Codex users may invoke it with natural language or
  `$developer-workflows`.

## Preserve Safety and Host Policy

Follow the selected workflow's scope and stop conditions. Obtain confirmation
where it explicitly requires confirmation, especially before creating an
issue, pushing changes, merging a PR, or deleting a branch. Host instructions,
repository instructions, sandbox rules, and user instructions take precedence
over workflow text.

When a workflow says to output another tool's result unchanged, keep that
result separate and avoid adding an independent review.
