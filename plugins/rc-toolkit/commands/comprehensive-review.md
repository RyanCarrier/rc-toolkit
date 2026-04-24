---
description: Run a comprehensive multi-agent PR review (Claude + Gemini + Codex)
model: sonnet
context: none
---

# Comprehensive Review

Run the `comprehensive-review` agent to perform a multi-agent PR review. This launches three independent reviews in parallel and consolidates the findings.

## Instructions

Invoke the `comprehensive-review` agent and output its full report to the user. Include failure reasons for any reviewer that didn't complete. Do not filter or validate the reviewers' findings — present them as-is.
