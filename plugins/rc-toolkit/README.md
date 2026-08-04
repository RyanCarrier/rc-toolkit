# rc-toolkit

Personal cross-project developer toolkit for Claude Code and OpenAI Codex.
Provides code review, CI debugging, GitHub, and git workflows.

## Commands

Native slash commands in Claude Code. Codex reaches the same workflows through
the `developer-workflows` skill — ask for them by name instead of by slash
command.

| Command | Description |
|---------|-------------|
| `/rc-toolkit:commit-push` | Stage, commit, and push changes in one step |
| `/rc-toolkit:quick-review` | Brief pre-commit code review (staged + unstaged) |
| `/rc-toolkit:local-review` | Thorough review of all unpushed changes |
| `/rc-toolkit:get-ci-failures` | Analyze the latest failing GitHub Actions run |
| `/rc-toolkit:get-copilot-review` | Fetch the most recent Copilot review on the current PR and validate its findings |
| `/rc-toolkit:handle-copilot-review` | Fetch the latest Copilot review, validate it, and fix the real issues |
| `/rc-toolkit:handle-issue` | Fetch a GitHub issue by number and plan the fix |
| `/rc-toolkit:create-issue` | Draft and open a new GitHub issue in the current repo |
| `/rc-toolkit:squash-merge` | Squash-merge current PR and delete branch (worktree-safe) |
| `/rc-toolkit:agy-review-pr` | Run an Antigravity (agy) code review on current branch |
| `/rc-toolkit:codex-review-local` | Run Codex code review on uncommitted local changes |
| `/rc-toolkit:codex-review-pr` | Run Codex code review on current branch vs main |
| `/rc-toolkit:multi-pr-review` | Multi-agent PR review (Claude + Antigravity + Codex) |
| `/rc-toolkit:breakdown-review` | Split a PR into logical sections and review each independently |
| `/rc-toolkit:validate-review` | Filter false positives out of an existing review's findings |
| `/rc-toolkit:plan-fixes` | Build a consolidated fix plan with per-fix justification, blast radius, and won't-fix calls |
| `/rc-toolkit:fix-rereview` | Fix review issues, run pre-commit checks, commit, push, re-review |
| `/rc-toolkit:review-loop` | Full loop: review → plan → implement → re-review until clean |
| `/rc-toolkit:ci-loop` | Wait for CI, fix failures, and retry until green or blocked |

## Agents

Claude Code only. Codex runs the equivalent work inline or through its own
subagents.

| Agent | Description |
|-------|-------------|
| `multi-pr-review` | Multi-agent PR review — runs Claude, Antigravity, and Codex reviews in parallel, then consolidates findings |
| `breakdown-review` | Splits a PR into logical sections and reviews each with a focused subagent |

## Skills

Available on both hosts.

| Skill | Description |
|-------|-------------|
| `auto-branch` | Fully autonomous feature development — implements, tests, creates PR, reviews, monitors CI, and summarizes |
| `developer-workflows` | Runs the command workflows above on hosts without native slash commands (Codex). Inert in Claude Code, which uses the commands directly |

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) — required by `get-ci-failures`, `get-copilot-review`
- [Antigravity CLI](https://antigravity.google/) (`agy`) — required by `agy-review-pr` (Google's successor to the Gemini CLI)
  - Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
  - Authenticate by running `agy` once (Google sign-in)
  - Plus the `code-review` plugin, which provides `/code-review:pr-code-review`: `agy plugin install code-review`
  - Headless permission allowlist: since agy 1.1.3, headless (`-p`) runs auto-deny any tool not in `permissions.allow` (`~/.gemini/antigravity-cli/settings.json`), aborting the review with `jetski: no output produced...` on stderr. Run the allowlist setup command in `docs/agy-troubleshooting.md` — notably `command(mkdir)` is required because the review flow's first step is a `mkdir ... && gh pr diff` compound command
- [Codex CLI](https://www.npmjs.com/package/@openai/codex) (`codex`) — required by `codex-review-local`, `codex-review-pr`
  - Authenticated via `codex login` or `OPENAI_API_KEY` environment variable
- [pr-review-toolkit](https://github.com/anthropics/claude-plugins-official) plugin — required by `multi-pr-review` agent
  - Install: `claude plugin add pr-review-toolkit --marketplace claude-plugins-official`
  - Claude Code only. Under Codex this reviewer has no equivalent, so
    `multi-pr-review` and `breakdown-review` substitute a native review for that
    leg and label it accordingly — two external reviewers plus one native,
    rather than the three available in Claude Code

## Installation

### Codex

The repository root doubles as a Codex marketplace via
`.agents/plugins/marketplace.json`. Register it and install the plugin:

```bash
# From a clone (or pass the path to one)
codex plugin marketplace add .

# Or straight from GitHub
codex plugin marketplace add RyanCarrier/rc-toolkit

codex plugin add rc-toolkit@rc-toolkit
```

Start a new Codex session after installing so its skills are loaded.

Codex exposes the toolkit through the `developer-workflows` and `auto-branch`
skills. Invoke them by describing the task naturally (for example, "run a quick
review") or explicitly with `$developer-workflows` / `$auto-branch`.

The existing `commands/` and `agents/` remain available to Claude Code, which
uses them directly as `/rc-toolkit:*` slash commands. The `developer-workflows`
skill adapts those same command definitions at runtime for hosts that have no
native slash commands, so both hosts share one set of workflow instructions.

`multi-pr-review` and `breakdown-review` delegate one of their three reviewers
to the Claude Code `pr-review-toolkit` plugin. Under Codex that reviewer has no
equivalent, so the skill substitutes a native review and labels it accordingly.

### Claude Code

#### Option 1: Marketplace (recommended)

```bash
claude plugin marketplace add RyanCarrier/rc-toolkit

# Install globally (available in all projects)
claude plugin install rc-toolkit

# Or install for current project only
claude plugin install rc-toolkit --scope project
```

#### Option 2: Plugin directory flag

```bash
claude --plugin-dir /path/to/rc-toolkit/plugins/rc-toolkit
```

#### Option 3: Manual (project or global)

Add to `.claude/settings.json` (project-level) or `~/.claude/settings.json` (global):

```json
{
  "plugins": [
    "/path/to/rc-toolkit/plugins/rc-toolkit"
  ]
}
```
