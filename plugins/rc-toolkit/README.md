# rc-toolkit

Personal cross-project developer toolkit for Claude Code. Provides code review, CI debugging, and git workflow commands.

## Commands

| Command | Description |
|---------|-------------|
| `/rc-toolkit:commit-push` | Stage, commit, and push changes in one step |
| `/rc-toolkit:quick-review` | Brief pre-commit code review (staged + unstaged) |
| `/rc-toolkit:local-review` | Thorough review of all unpushed changes |
| `/rc-toolkit:get-ci-failures` | Analyze the latest failing GitHub Actions run |
| `/rc-toolkit:handle-copilot-review` | Fetch and triage Copilot's PR review |
| `/rc-toolkit:handle-issue` | Fetch a GitHub issue by number and plan the fix |
| `/rc-toolkit:create-issue` | Draft and open a new GitHub issue in the current repo |
| `/rc-toolkit:squash-merge` | Squash-merge current PR and delete branch (worktree-safe) |
| `/rc-toolkit:agy-review-pr` | Run an Antigravity (agy) code review on current branch |
| `/rc-toolkit:codex-review-local` | Run Codex code review on uncommitted local changes |
| `/rc-toolkit:codex-review-pr` | Run Codex code review on current branch vs main |
| `/rc-toolkit:multi-pr-review` | Multi-agent PR review (Claude + Antigravity + Codex) |

## Agents

| Agent | Description |
|-------|-------------|
| `multi-pr-review` | Multi-agent PR review — runs Claude, Antigravity, and Codex reviews in parallel, then consolidates findings |

## Skills

| Skill | Description |
|-------|-------------|
| `auto-branch` | Fully autonomous feature development — implements, tests, creates PR, reviews, monitors CI, and summarizes |

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) — required by `get-ci-failures`, `handle-copilot-review`
- [Antigravity CLI](https://antigravity.google/) (`agy`) — required by `agy-review-pr` (Google's successor to the Gemini CLI)
  - Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
  - Authenticate by running `agy` once (Google sign-in)
  - Plus the `code-review` plugin, which provides `/code-review:pr-code-review`: `agy plugin install code-review`
- [Codex CLI](https://www.npmjs.com/package/@openai/codex) (`codex`) — required by `codex-review-local`, `codex-review-pr`
  - Authenticated via `codex login` or `OPENAI_API_KEY` environment variable
- [pr-review-toolkit](https://github.com/anthropics/claude-plugins-official) plugin — required by `multi-pr-review` agent
  - Install: `claude plugin add pr-review-toolkit --marketplace claude-plugins-official`

## Installation

### Option 1: Marketplace (recommended)

```bash
claude plugin marketplace add RyanCarrier/rc-toolkit

# Install globally (available in all projects)
claude plugin install rc-toolkit

# Or install for current project only
claude plugin install rc-toolkit --scope project
```

### Option 2: Plugin directory flag

```bash
claude --plugin-dir /path/to/rc-toolkit/plugins/rc-toolkit
```

### Option 3: Manual (project or global)

Add to `.claude/settings.json` (project-level) or `~/.claude/settings.json` (global):

```json
{
  "plugins": [
    "/path/to/rc-toolkit/plugins/rc-toolkit"
  ]
}
```
