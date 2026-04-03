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
| `/rc-toolkit:gemini-code-review` | Run Gemini's code-review extension on current branch |

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) — required by `get-ci-failures`, `handle-copilot-review`
- [Gemini CLI](https://www.npmjs.com/package/@google/gemini-cli) (`gemini`) — required by `gemini-code-review`
  - Plus the code-review extension: `gemini extensions install https://github.com/gemini-cli-extensions/code-review`
  - `GEMINI_API_KEY` environment variable set

## Installation

### Option 1: Marketplace (recommended)

```bash
claude plugin marketplace add RyanCarrier/rc-toolkit
claude plugin install rc-toolkit
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
