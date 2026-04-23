---
description: Run a Gemini code review using the code-review extension (experimental)
model: haiku
context: none
allowed-tools: Bash(mkdir:*), Bash(gemini:*), Read
---

# Gemini Code Review

Uses Gemini's `code-review` extension to autonomously gather diffs and perform a code review.

Runs in `plan` approval mode so Gemini's internal tool calls (like `git diff`) are read-only.

**Prerequisite:** The extension must be installed:
```
gemini extensions install https://github.com/gemini-cli-extensions/code-review
```

## Instructions

**CRITICAL:** Your ONLY job is to run the exact Bash command below and output the result. Do NOT skip, modify, or "improve" the command. Do NOT substitute a different model name. Execute it exactly as written.

### Step 1: Run Gemini Code Review

Run this exact command using the Bash tool with a 300s timeout. Do NOT change any flags or arguments:

```bash
mkdir -p tmp && gemini --model gemini-3.1-pro-preview -p "/code-review" --approval-mode plan -e code-review 2>tmp/gemini_code_review_ext_error.txt
```

**Model:** The model MUST be `gemini-3.1-pro-preview` — exactly as shown above. Do NOT substitute any other model name (e.g. `gemini-pro`, `gemini-1.5-pro`, `gemini-2.0-flash`, `gemini-2.5-pro`). Use `gemini-3.1-pro-preview` verbatim.

### Step 2: Output the Result

Output the raw Gemini response text directly to the user. Do not summarize or modify it.

If the command produces no stdout response, read `tmp/gemini_code_review_ext_error.txt` and report the error to the user. Common issues:

- `GEMINI_API_KEY` not set
- `gemini` CLI not installed (`npm install -g @google/gemini-cli`)
- `code-review` extension not installed (`gemini extensions install https://github.com/gemini-cli-extensions/code-review`)
- Model not available or rate limited
