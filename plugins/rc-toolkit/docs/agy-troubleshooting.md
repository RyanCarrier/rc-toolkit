# agy Headless Review Troubleshooting

Reference for failures of the `agy-review-pr` command. Read this only when a review run fails.

## Permission soft-denial (`jetski: no output produced`)

Since agy 1.1.3, headless (`-p`) runs cannot show permission prompts, so any tool call not covered by `permissions.allow` in `~/.gemini/antigravity-cli/settings.json` is auto-denied and the whole review aborts with exit 0 and empty stdout. Every command in a compound chain (`a && b`) must match an allow rule — the review flow's first step is `mkdir -p ~/.gemini/antigravity-cli/brain/<id>/scratch/ && gh pr diff > ...`, so `command(mkdir)` is required even though `gh pr` is allowlisted.

When this error appears, tell the user to run this command to install the allow rules the review flow needs (idempotent — merges with existing rules):

```bash
jq '.permissions.allow = ((.permissions.allow // []) + [
  "command(mkdir)",
  "command(git status)", "command(git log)", "command(git diff)", "command(git show)",
  "command(git branch)", "command(git rev-parse)", "command(git ls-files)", "command(git merge-base)",
  "command(git remote)", "command(git ls-tree)", "command(git cat-file)", "command(git blame)", "command(git describe)",
  "command(gh pr)", "command(gh api)", "command(gh repo view)", "command(gh search)", "command(gh browse)",
  "command(cat)", "command(head)", "command(tail)", "command(sed)", "command(grep)", "command(rg)",
  "command(ls)", "command(wc)", "command(find)", "command(awk)", "command(jq)", "command(diff)",
  "command(sort)", "command(uniq)", "command(cut)", "command(tr)", "command(echo)", "command(basename)",
  "command(dirname)", "command(stat)", "command(file)", "command(xargs)"
] | unique)' ~/.gemini/antigravity-cli/settings.json > /tmp/agy_settings.json && mv -f /tmp/agy_settings.json ~/.gemini/antigravity-cli/settings.json
```

If the error persists, a different command is being denied. To identify it, tell the user to run:

```bash
grep -n "soft-denying" ~/.gemini/antigravity-cli/log/cli-*.log | tail -3
```

The log line after the soft-deny names the conversation ID; the exact denied command is in the `step_payload` blob of the `steps` table in `~/.gemini/antigravity-cli/conversations/<id>.db` (extract with `sqlite3` + `strings`). Add a matching `command(<first-token>)` rule and rerun. Last-resort fallback: rerun with `--dangerously-skip-permissions` (auto-approves everything — bypasses the curated allowlist).

## Workspace trust

`trustedWorkspaces` in the same settings file is exact-path matched (a parent dir does not trust subdirs), and untrusted folders get silently redirected to a scratch workspace (`~/.gemini/antigravity-cli/scratch`) — but `--add-dir "$(pwd)"` in the review command already handles this, so no per-worktree trust setup is needed.
