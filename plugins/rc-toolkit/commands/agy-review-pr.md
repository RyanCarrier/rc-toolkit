---
description: Run an Antigravity (agy) code review on the current branch
model: haiku
context: none
allowed-tools: Bash(mkdir:*), Bash(agy:*), Bash(gh pr diff:*), Bash(git diff:*), Read
argument-hint: [--range from..to] [review instructions]
---

# Antigravity (agy) Code Review

Uses the Antigravity CLI (`agy`) and its `code-review` plugin to autonomously gather the PR diff and perform a code review. `agy` is Google's successor to the Gemini CLI.

## Arguments

`$ARGUMENTS` may carry:

- `--range <from>..<to>` — the diff agy reads is `git diff <from>..<to>` instead of the GitHub PR diff, so the review covers only those commits. `review-loop` uses this to re-review just the fix commits of an iteration.
- Any remaining text is a **review brief**: append it to the `-p` prompt as a final `REVIEW BRIEF: <text>` paragraph, after the OUTPUT OVERRIDE block. Multi-pr-review passes its reviewer brief (and, in delta mode, the per-fix verification instructions) this way.

**Base branch:** The `pr-code-review` command fetches the **GitHub PR diff** (via the `pull_request_read` tools). GitHub computes that diff against the PR's actual base branch, so the review automatically compares against the PR's base — not `main` — even for stacked PRs based on another branch. `--add-dir "$(pwd)"` grants `agy` access to the local repo for additional context.

**Prerequisites:**
- `agy` installed and authenticated (run `agy` once to sign in with Google via OAuth).
- The `code-review` plugin installed, which provides the `/code-review:pr-code-review` command. Install it directly with `agy plugin install code-review`, or import an existing Gemini CLI `code-review` extension with `agy plugin import gemini`.

## Instructions

**CRITICAL:** Your job is to run the exact Bash commands below and output the result. Do NOT skip, modify, or "improve" them. Do NOT substitute a different model name. Execute them exactly as written — the only permitted substitutions are the two named in Step 1 for `--range` and the review brief. Run the **Step 0 warm-up first**; only run the Step 1 review once the warm-up has passed.

### Step 0: Warm Up agy (Health Check)

`agy` frequently fails on its **first** invocation of a session — cold start, auth-token refresh, or model spin-up — but succeeds on a retry. Spending that first failure on the expensive review request wastes it and can abort the whole review silently (see Step 2: an aborted run returns exit 0 with empty stdout, indistinguishable from a clean review). So first run a cheap "hello world" health check and let it absorb the cold start.

Run this exact command with the Bash tool, setting the tool's **`timeout` to `300000` (5 minutes)**. A trivial prompt returns in seconds, so 5 minutes is a deliberately generous ceiling; if `agy` hangs, the timeout kills it and counts as a failed attempt.

```bash
mkdir -p tmp && agy --add-dir "$(pwd)" --model "Gemini 3.7 Flash (High)" -p "Reply with exactly this token and nothing else: AGY_WARMUP_OK" 2>tmp/agy_warmup_error.txt
```

**Model:** MUST be the same model string as Step 1 (`"Gemini 3.7 Flash (High)"`). Keeping them identical means the warm-up exercises the exact auth + model path the review uses, so a pass is a real signal — and it catches model-unavailable / rate-limit / the non-TTY stdout-drop failure before the expensive call. If you ever change the model in Step 1, change it here too. `--add-dir "$(pwd)"` matches Step 1 and grants `agy` the same workspace trust, so the warm-up runs in the same context the review will. The `2>tmp/...` redirect is the *outer* shell's, not agy's, so it is fine (same as Step 1).

**Evaluate each attempt:**

- **PASS** — stdout contains the token `AGY_WARMUP_OK`. `agy` is healthy. Proceed to Step 1 immediately and do NOT warm up again.
- **FAIL** — stdout is empty, stdout does not contain `AGY_WARMUP_OK`, or the attempt errored or hit the 5-minute timeout.

**Retry policy:** on FAIL, run the *exact same command again* — up to **3 attempts total**. Stop the moment one attempt PASSES.

**If all 3 attempts FAIL, return early — do NOT run Step 1, and do NOT fabricate a review.** A failed warm-up means the review did not run; it is not "no issues found." Emit exactly this as the **first line** of your output so the parent consolidator (multi-/breakdown-review) can detect it mechanically — it is the same `AGY REVIEW FAILED:` marker described in Step 2:

```
AGY REVIEW FAILED: agy warm-up health check failed after 3 attempts — <one-line reason from tmp/agy_warmup_error.txt>
```

Below that line, include the last attempt's stderr (`tmp/agy_warmup_error.txt`) and the relevant common causes listed in Step 2 (not installed / not authenticated / `code-review` plugin missing / model unavailable or rate limited), then stop.

### Step 1: Run the Antigravity Code Review

Run this exact command using the Bash tool with a 600s timeout. Do NOT change any flags or arguments. The only permitted substitutions: (1) when `--range <from>..<to>` was given, replace `gh pr diff > tmp/pr.diff` with `git diff <from>..<to> > tmp/pr.diff`; (2) when a review brief was given, append a final paragraph `REVIEW BRIEF: <text>` to the `-p` prompt, after the OUTPUT OVERRIDE paragraph.

```bash
mkdir -p tmp && gh pr diff > tmp/pr.diff && agy --add-dir "$(pwd)" --model "Gemini 3.7 Flash (High)" --print-timeout 9m30s -p "/code-review:pr-code-review

DIFF SOURCE: The PR diff has already been fetched to 'tmp/pr.diff' in the workspace. Read that file to get the diff. Do NOT run 'gh pr diff' or otherwise re-fetch it.

SHELL OVERRIDE: Do NOT redirect command output to files. Do not use '>', '>>', or '2>&1' in any run_command call, and do not pipe output into tee. Headless permission checks require an exact-match allow rule for any command containing a redirect, so a redirected command is auto-denied and the whole review aborts with no output.

ALLOWED COMMANDS: You may run shell commands (run_command/RunCommand) ONLY from the explicit allowlist below. Headless mode cannot prompt for permission and auto-denies any command it has not pre-approved, aborting the whole review with empty stdout — so a single command outside this list kills the run. Do NOT reach for anything not listed here (no python3, node, package managers, build/format/test runners, network calls, or file writes), even if it looks helpful; note the limitation in a finding and proceed instead. Prefer your file-reading and file-search tools for reading source; use these commands only when a tool cannot get the context. You may NOT write or modify any file (no redirects, no in-place edits, no scratch files). Invoke each command exactly by the leading tokens shown — a flag inserted before them (e.g. 'git --no-pager log') breaks the permission match unless that exact form is listed.

  - git (read-only): git status, git log, git diff, git show, git branch, git rev-parse, git ls-files, git merge-base, git remote, git ls-tree, git cat-file, git blame, git describe, git rev-list, git for-each-ref, git shortlog, git tag, git show-ref, git name-rev, git grep, git diff-tree, and 'git --no-pager diff|log|show'
  - gh (read-only): gh pr view, gh pr diff, gh pr list, gh pr checks, gh pr status, gh api, gh repo view, gh issue view, gh issue list, gh run list, gh run view, gh workflow view, gh search, gh browse
  - file/text inspection: cat, head, tail, nl, sed, grep, rg, ls, tree, find, wc, awk, jq, diff, sort, uniq, comm, cut, paste, column, tr, echo, printf, basename, dirname, realpath, readlink, stat, file, which, pwd, date, seq, xargs

NO SPECULATION: Do not report a finding that depends on a fact you cannot verify from the files in this workspace — e.g. whether an external action/package version or tag exists, or how a remote API behaves. Pinned dependency versions are resolved deterministically by CI and fail loudly, so never flag them as possibly-missing. If a claim would need network access or a command outside the allowlist above to confirm, omit it or mark it clearly as UNVERIFIED; never present it as a definite issue.

OUTPUT OVERRIDE: Do NOT post this review to GitHub. Do NOT call create_pending_pull_request_review, add_comment_to_pending_review, or submit_pending_pull_request_review, and do NOT create any pending review or inline PR comments. Instead, write the complete review (summary plus every finding with file:line and severity) as plain text in your final response so it can be consolidated." 2>tmp/agy_code_review_error.txt
```

**Timeout:** The Bash tool `timeout` stays at **600s (10 min)** — the harness maximum, so it cannot go higher on a stock install. `--print-timeout 9m30s` tells `agy` to stop waiting ~30s *before* that hard kill, so an overrunning review ends with `agy`'s own graceful timeout message (and a populated `tmp/agy_code_review_error.txt`) instead of an abrupt Bash kill that looks identical to the empty-stdout failure in Step 2. Without the flag, `agy` print mode defaults to a **5-minute** wait — too short for large diffs, which is why it is set explicitly. Keep `--print-timeout` just under the Bash `timeout`: if you raise one, raise the other — but note the Bash tool cannot exceed `600000` ms unless `BASH_MAX_TIMEOUT_MS` is raised in settings, which this plugin cannot do for its users.

**Model:** The model MUST be `"Gemini 3.7 Flash (High)"` — exactly as shown above, including the quotes and capitalization. This is an Antigravity model display string (run `agy models` to see the available list), NOT a Gemini API id. The `(High)` suffix selects the highest reasoning effort and must be kept — do NOT drop to `(Medium)`/`(Low)`. Do NOT substitute any other value (e.g. the API id `gemini-3.7-flash-high`, `gemini-flash`, or an older model like `Gemini 3.1 Pro (High)`).

**Diff source:** The outer command fetches the diff itself with `gh pr diff > tmp/pr.diff` and points `agy` at the file. That redirect runs in *your* shell, which permits it — the restriction applies only to commands `agy` runs. This removes the dominant failure by construction rather than relying on `agy` choosing a non-redirecting command every run, and it preserves the base-branch behaviour described above, since `gh pr diff` returns the same GitHub-computed diff the plugin would fetch. If there is no PR for the current branch the chain fails fast with a visible `gh` error, which is the desired outcome — better than `agy` aborting silently.

**Shell override:** Kept as defence in depth, since `agy` may still reach for a redirect on its own. Historically the single most common cause of a silent empty review. Since agy 1.1.3, headless (`-p`) runs cannot prompt for permissions, and agy enforces **exact-match** verification for any command containing a shell redirect (`>`, `>>`, `2>&1`) — prefix rules like `command(gh pr diff)` do not cover them. The `code-review` plugin's default flow saves the diff with `gh pr diff <N> > scratch/pr<N>.diff`, whose target path varies per run, so no static allow rule can ever match it and the review aborts with exit 0 and empty stdout. Telling agy not to redirect keeps the whole flow inside the prefix-matched allowlist. Do NOT remove it. The `2>tmp/...` at the end of the command is the *outer* shell's redirect, not agy's — it is fine and must stay.

**Allowed commands:** Even with redirects handled, `agy` (an agentic model) otherwise invents novel inspection commands each run — including ones that *write* scratch files or shell out to `python3` — and headless mode auto-denies any command not pre-allowed in `~/.gemini/antigravity-cli/settings.json`, aborting the review with empty stdout. The ALLOWED COMMANDS block pins `agy` to the read-only inspection commands that are actually in the `permissions.allow` allowlist, so it can verify context without tripping a soft-denial. The list is deliberately a **read-only subset** of `permissions.allow` — it omits writes, `python3`/`node`, and build/format/test runners even where those are allowlisted, to keep the no-writes guarantee. Keep the prompt list in sync with the `permissions.allow` setup in `${CLAUDE_PLUGIN_ROOT}/docs/agy-troubleshooting.md`. The **NO SPECULATION** rule stays paired with it: a bounded command set still cannot confirm external facts (whether a pinned action/tag exists, how a remote API behaves), so unverifiable findings must be suppressed. Do NOT remove either block.

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
- Review hit the timeout — Step 1 already sets `--print-timeout 9m30s`, just under the 600s (10-min) Bash `timeout` ceiling. A review that needs longer cannot fit a stock harness's 10-min Bash cap; either narrow the diff (e.g. review with `--range`) or, only where you control the session, raise `BASH_MAX_TIMEOUT_MS` in settings and bump both the Bash `timeout` and `--print-timeout` together
- Permission soft-denial (`jetski: no output produced — a tool required the "command" permission...`) — the ALLOWED COMMANDS list above makes this rare; if it recurs, `agy` reached for a command outside the list (or one carrying a redirect). Read `${CLAUDE_PLUGIN_ROOT}/docs/agy-troubleshooting.md`; the `permissions.allow` allowlist there must be a superset of the prompt's list.
