# agy Headless Review Troubleshooting

Reference for failures of the `agy-review-pr` command. Read this only when a review run fails.

## First-run cold start (handled by the Step 0 warm-up)

`agy` frequently fails on its **first** invocation of a session (cold start, auth-token refresh, or model spin-up) and then succeeds on a retry. `agy-review-pr.md` absorbs this with a **Step 0 warm-up**: before the real review it runs a trivial `agy --add-dir "$(pwd)" --model "..." -p "Reply with exactly this token and nothing else: AGY_WARMUP_OK"` health check (Bash tool `timeout` = 300000 ms / 5 min per attempt), retrying up to 3 times until stdout contains the token. Only after a pass does Step 1 run, so the expensive review request is no longer the one that eats the cold-start failure.

If all 3 warm-up attempts fail, the command returns early with `AGY REVIEW FAILED: agy warm-up health check failed after 3 attempts — ...` instead of running the review — the same marker the consolidators treat as a dead reviewer. When that happens, the cause is real (not a transient cold start): check the causes below, and the last attempt's stderr in `tmp/agy_warmup_error.txt`. Keep the warm-up model string identical to Step 1's so the health check exercises the same auth + model path.

## Shell redirects are auto-denied and cannot be allowlisted

**Check this first — it is the most common cause of a silent empty review.**

agy enforces *exact-match* verification for any command containing a complex shell redirect (`>`, `>>`, `2>&1`) or command substitution (`$(...)`), as hardening against sandbox escapes. Prefix rules do **not** apply to such commands. So `command(gh pr diff)` permits `gh pr diff` but **not** `gh pr diff 643 > scratch/pr643.diff`.

Because the plugin's redirect targets vary per run (PR number, scratch path, `/tmp` vs repo-relative), **no static allow rule can match them.** Rules shaped like `command(gh pr diff >)` or `command(git diff >)` look plausible but are dead entries — they never match anything. Delete them rather than adding more.

Verify with a two-line A/B in any repo:

```bash
agy --add-dir "$(pwd)" -p "Run exactly this and nothing else: echo hello"                  # succeeds
agy --add-dir "$(pwd)" -p "Run exactly this and nothing else: echo hello > /tmp/x.txt"     # soft-denied
```

`command(echo)` is allowlisted in both cases; only the redirect differs.

**The fix is the SHELL OVERRIDE block in `agy-review-pr.md`**, which instructs agy not to redirect at all. If a review still aborts, confirm that block is still present in the prompt before touching the allowlist. `--sandbox` alone does not help — it does not change headless permission matching.

## Permission soft-denial (`jetski: no output produced`)

**Primary fix (the ALLOWED COMMANDS prompt):** the review command pins `agy` to an explicit read-only allowlist and tells it to run nothing else, so it verifies context with commands that are actually approved instead of inventing novel ones (some that *write* files or run `python3`) that get auto-denied. The prompt's list must stay a **subset** of `permissions.allow` below — every command the prompt names has to have a matching allow rule here, or it is soft-denied despite being on the prompt list. The notes here apply when a soft-denial happens anyway — i.e. `agy` reached for a command outside its list, or one carrying a redirect (see the section above).

Since agy 1.1.3, headless (`-p`) runs cannot show permission prompts, so any tool call not covered by `permissions.allow` in `~/.gemini/antigravity-cli/settings.json` is auto-denied and the whole review aborts with exit 0 and empty stdout. Every command in a compound chain (`a && b`) must match an allow rule — so `command(mkdir)` is required for a `mkdir ... && gh pr diff` chain even though `gh pr` is allowlisted.

Note that a rule matches on the command's **leading tokens**, so a flag between them breaks the match: `git --no-pager diff` is not covered by `command(git diff)` and needs its own `command(git --no-pager diff)` rule.

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
  "command(dirname)", "command(stat)", "command(file)", "command(xargs)",
  "command(git --no-pager diff)", "command(git --no-pager log)", "command(git --no-pager show)"
] | unique)' ~/.gemini/antigravity-cli/settings.json > /tmp/agy_settings.json && mv -f /tmp/agy_settings.json ~/.gemini/antigravity-cli/settings.json
```

Do not add redirect-shaped rules to this list — see the section above for why they cannot work.

If the error persists, a different command is being denied. To identify it, tell the user to run:

```bash
grep -n "soft-denying" ~/.gemini/antigravity-cli/log/cli-*.log | tail -3
```

The log line after the soft-deny names the conversation ID; the exact denied command is in the `step_payload` blob of the `steps` table in `~/.gemini/antigravity-cli/conversations/<id>.db` (extract with `sqlite3` + `strings`). Add a matching `command(<first-token>)` rule and rerun. Last-resort fallback: rerun with `--dangerously-skip-permissions` (auto-approves everything — bypasses the curated allowlist).

## Workspace trust

`trustedWorkspaces` in the same settings file is exact-path matched (a parent dir does not trust subdirs), and untrusted folders get silently redirected to a scratch workspace (`~/.gemini/antigravity-cli/scratch`) — but `--add-dir "$(pwd)"` in the review command already handles this, so no per-worktree trust setup is needed.
