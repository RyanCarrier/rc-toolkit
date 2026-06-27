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
mkdir -p tmp && agy --add-dir "$(pwd)" --model "Gemini 3.1 Pro (High)" -p "/code-review:pr-code-review

OUTPUT OVERRIDE: Do NOT post this review to GitHub. Do NOT call create_pending_pull_request_review, add_comment_to_pending_review, or submit_pending_pull_request_review, and do NOT create any pending review or inline PR comments. Instead, write the complete review (summary plus every finding with file:line and severity) as plain text in your final response so it can be consolidated." 2>tmp/agy_code_review_error.txt
```

**Model:** The model MUST be `"Gemini 3.1 Pro (High)"` — exactly as shown above, including the quotes and capitalization. This is an Antigravity model display string (run `agy models` to see the available list), NOT a Gemini API id. Do NOT substitute any other value (e.g. `gemini-3.1-pro-preview`, `gemini-pro`, `Gemini 3.5 Flash`).

**Output override:** The extra prompt text after `/code-review:pr-code-review` is intentional and must be kept. By default the `pr-code-review` command posts its findings to the GitHub PR as inline review comments. This toolkit needs the review returned as text (it is captured by Step 2 and fed to the multi-/breakdown-review consolidators), so the override tells `agy` to skip the GitHub submission tools and just print the review. Do NOT remove it.

### Step 2: Output the Result

Output the raw `agy` response text directly to the user. Do not summarize or modify it.

If the command produces no stdout response, read `tmp/agy_code_review_error.txt` and report the error to the user. Common issues:

- `agy` CLI not installed (`curl -fsSL https://antigravity.google/cli/install.sh | bash`)
- `agy` not authenticated — run `agy` once interactively to sign in with Google
- `code-review` plugin not installed (`agy plugin install code-review`) — this provides the `/code-review:pr-code-review` command
- Model not available or rate limited
- Review exceeded print mode's default 5m wait — rerun with a longer `--print-timeout` (e.g. `--print-timeout 15m`)
