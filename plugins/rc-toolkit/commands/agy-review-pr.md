---
description: Run an Antigravity (agy) code review on the current branch
model: haiku
context: none
allowed-tools: Bash(mkdir:*), Bash(agy:*), Read
---

# Antigravity (agy) Code Review

Uses the Antigravity CLI (`agy`) and its `code-review` plugin to autonomously gather the PR diff and perform a code review. `agy` is Google's successor to the Gemini CLI.

**Prerequisites:**
- `agy` installed and authenticated (run `agy` once to sign in with Google via OAuth).
- The `code-review` plugin installed, which provides the `/code-review:pr-code-review` command. Install it directly with `agy plugin install code-review`, or import an existing Gemini CLI `code-review` extension with `agy plugin import gemini`.

## Instructions

**CRITICAL:** Your ONLY job is to run the exact Bash command below and output the result. Do NOT skip, modify, or "improve" the command. Do NOT substitute a different model name. Execute it exactly as written.

### Step 1: Run the Antigravity Code Review

Run this exact command using the Bash tool with a 600s timeout. Do NOT change any flags or arguments:

```bash
mkdir -p tmp && agy --model "Gemini 3.1 Pro (High)" -p "/code-review:pr-code-review" 2>tmp/agy_code_review_error.txt
```

**Model:** The model MUST be `"Gemini 3.1 Pro (High)"` — exactly as shown above, including the quotes and capitalization. This is an Antigravity model display string (run `agy models` to see the available list), NOT a Gemini API id. Do NOT substitute any other value (e.g. `gemini-3.1-pro-preview`, `gemini-pro`, `Gemini 3.5 Flash`).

### Step 2: Output the Result

Output the raw `agy` response text directly to the user. Do not summarize or modify it.

If the command produces no stdout response, read `tmp/agy_code_review_error.txt` and report the error to the user. Common issues:

- `agy` CLI not installed (`curl -fsSL https://antigravity.google/cli/install.sh | bash`)
- `agy` not authenticated — run `agy` once interactively to sign in with Google
- `code-review` plugin not installed (`agy plugin install code-review`) — this provides the `/code-review:pr-code-review` command
- Model not available or rate limited
- Review exceeded print mode's default 5m wait — rerun with a longer `--print-timeout` (e.g. `--print-timeout 15m`)
