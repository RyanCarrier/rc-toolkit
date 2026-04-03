---
description: Run a Gemini code review using the code-review extension (experimental)
model: haiku
context: none
allowed-tools: Bash(gemini:*), Read
---

# Gemini Code Review

Uses Gemini's `code-review` extension to autonomously gather diffs and perform a code review.

Runs in `plan` approval mode so Gemini's internal tool calls (like `git diff`) are read-only.

**Prerequisite:** The extension must be installed:
```
gemini extensions install https://github.com/gemini-cli-extensions/code-review
```

## Instructions

### Step 1: Run Gemini Code Review

Always use the `/code-review` prompt. Run with `plan` approval mode so Gemini can execute read-only operations (like git diff) without manual approval:

```bash
gemini --model gemini-3.1-pro-preview -p "/code-review" --approval-mode plan -e code-review 2>tmp/gemini_code_review_ext_error.txt
```

Set a generous timeout (300s) as Gemini will make multiple tool calls.

### Step 2: Output the Result

Output the raw Gemini response text directly to the user. Do not summarize or modify it.

If the command produces no stdout response, read `tmp/gemini_code_review_ext_error.txt` and report the error to the user. Common issues:

- `GEMINI_API_KEY` not set
- `gemini` CLI not installed (`npm install -g @google/gemini-cli`)
- `code-review` extension not installed (`gemini extensions install https://github.com/gemini-cli-extensions/code-review`)
- Model not available or rate limited
