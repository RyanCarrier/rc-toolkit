---
description: Run an Antigravity (agy) code review on the current branch
model: haiku
context: none
allowed-tools: Bash(mkdir:*), Bash(agy:*), Read
---

# Antigravity (agy) Code Review

Uses the Antigravity CLI (`agy`) and its `code-review` plugin to autonomously gather the PR diff and perform a code review. `agy` is Google's successor to the Gemini CLI.

**Base branch:** The `pr-code-review` command fetches the **GitHub PR diff** (via the `pull_request_read` tools). GitHub computes that diff against the PR's actual base branch, so the review automatically compares against the PR's base — not `main` — even for stacked PRs based on another branch. `--add-dir "$(pwd)"` grants `agy` access to the local repo for additional context.

**Prerequisites:**
- `agy` installed and authenticated (run `agy` once to sign in with Google via OAuth).
- The `code-review` plugin installed, which provides the `/code-review:pr-code-review` command. Install it directly with `agy plugin install code-review`, or import an existing Gemini CLI `code-review` extension with `agy plugin import gemini`.

## Instructions

**CRITICAL:** Your ONLY job is to run the exact Bash command below and output the result. Do NOT skip, modify, or "improve" the command. Do NOT substitute a different model name. Execute it exactly as written.

### Step 1: Run the Antigravity Code Review

Run this exact command using the Bash tool with a 600s timeout. Do NOT change any flags or arguments:

```bash
mkdir -p tmp && gh pr diff > tmp/pr.diff && agy --add-dir "$(pwd)" --model "Gemini 3.1 Pro (High)" -p "/code-review:pr-code-review

DIFF SOURCE: The PR diff has already been fetched to 'tmp/pr.diff' in the workspace. Read that file to get the diff. Do NOT run 'gh pr diff' or otherwise re-fetch it.

SHELL OVERRIDE: Do NOT redirect command output to files. Do not use '>', '>>', or '2>&1' in any run_command call, and do not pipe output into tee. Headless permission checks require an exact-match allow rule for any command containing a redirect, so a redirected command is auto-denied and the whole review aborts with no output.

You MAY read files, search the codebase, and run read-only inspection commands (git log, git show, git blame, grep, rg, cat, ls, find) to understand the context around a change — that context is what separates a real finding from a false positive. You may NOT write or modify any file.

OUTPUT OVERRIDE: Do NOT post this review to GitHub. Do NOT call create_pending_pull_request_review, add_comment_to_pending_review, or submit_pending_pull_request_review, and do NOT create any pending review or inline PR comments. Instead, write the complete review (summary plus every finding with file:line and severity) as plain text in your final response so it can be consolidated." 2>tmp/agy_code_review_error.txt
```

**Model:** The model MUST be `"Gemini 3.1 Pro (High)"` — exactly as shown above, including the quotes and capitalization. This is an Antigravity model display string (run `agy models` to see the available list), NOT a Gemini API id. Do NOT substitute any other value (e.g. `gemini-3.1-pro-preview`, `gemini-pro`, `Gemini 3.5 Flash`).

**Diff source:** The outer command fetches the diff itself with `gh pr diff > tmp/pr.diff` and points `agy` at the file. That redirect runs in *your* shell, which permits it — the restriction applies only to commands `agy` runs. This removes the dominant failure by construction rather than relying on `agy` choosing a non-redirecting command every run, and it preserves the base-branch behaviour described above, since `gh pr diff` returns the same GitHub-computed diff the plugin would fetch. If there is no PR for the current branch the chain fails fast with a visible `gh` error, which is the desired outcome — better than `agy` aborting silently.

**Shell override:** Kept as defence in depth, since `agy` may still reach for a redirect on its own. Historically the single most common cause of a silent empty review. Since agy 1.1.3, headless (`-p`) runs cannot prompt for permissions, and agy enforces **exact-match** verification for any command containing a shell redirect (`>`, `>>`, `2>&1`) — prefix rules like `command(gh pr diff)` do not cover them. The `code-review` plugin's default flow saves the diff with `gh pr diff <N> > scratch/pr<N>.diff`, whose target path varies per run, so no static allow rule can ever match it and the review aborts with exit 0 and empty stdout. Telling agy not to redirect keeps the whole flow inside the prefix-matched allowlist. Do NOT remove it. The `2>tmp/...` at the end of the command is the *outer* shell's redirect, not agy's — it is fine and must stay.

**Output override:** The extra prompt text after `/code-review:pr-code-review` is intentional and must be kept. By default the `pr-code-review` command posts its findings to the GitHub PR as inline review comments. This toolkit needs the review returned as text (it is captured by Step 2 and fed to the multi-/breakdown-review consolidators), so the override tells `agy` to skip the GitHub submission tools and just print the review. Do NOT remove it.

### Step 2: Output the Result

Output the raw `agy` response text directly to the user. Do not summarize or modify it.

**If stdout is empty, the review FAILED — it did not find zero issues.** `agy` aborts with exit 0 and empty stdout on a permission soft-denial, so a failed run is indistinguishable from a clean one by exit code alone. Never report an empty result as "no issues found"; a consumer that treats it that way counts a dead reviewer as a passing vote.

On empty stdout, read `tmp/agy_code_review_error.txt` and emit exactly this line as the first line of your output, so callers can detect it mechanically:

```
AGY REVIEW FAILED: <one-line reason from the stderr file>
```

Then report the detail below it. Common issues:

- `agy` CLI not installed (`curl -fsSL https://antigravity.google/cli/install.sh | bash`)
- `agy` not authenticated — run `agy` once interactively to sign in with Google
- `code-review` plugin not installed (`agy plugin install code-review`) — this provides the `/code-review:pr-code-review` command
- Model not available or rate limited
- Review exceeded print mode's default 5m wait — rerun with a longer `--print-timeout` (e.g. `--print-timeout 15m`)
- Permission soft-denial (`jetski: no output produced — a tool required the "command" permission...`) — Read `${CLAUDE_PLUGIN_ROOT}/docs/agy-troubleshooting.md` and follow its instructions
