---
description: Fetch the latest Copilot PR review, validate it, and fix the real issues
model: opus
---

# Handle Copilot PR Review

Fetch and validate the most recent Copilot review (in one step, via `get-copilot-review`), then fix the findings that survive validation.

Copilot reviews carry a high false-positive rate — it reasons from diff context and routinely flags concerns the surrounding code already handles. `get-copilot-review` already runs the validation pass that filters those out; this command consumes the result and acts on it.

## Instructions

### Step 1: Fetch and Validate the Review

Run the fetch through a subagent so the results return to you for evaluation. `get-copilot-review` fetches the latest Copilot review **and validates it** in the same step, so what returns is already a filtered issue set — you do not run a separate validation pass. **Do NOT call `Skill()` directly** — it takes over the turn and prevents you from continuing to Step 2 in the same response.

```
Agent(
  description="Get and validate Copilot review",
  prompt="Fetch and validate the most recent GitHub Copilot review on the current PR. Invoke Skill(skill='rc-toolkit:get-copilot-review'). Return the complete validated report exactly as produced — the VALID issues by severity and the INVALID ones with dismissal reasons. Do not add your own analysis."
)
```

If the subagent reports no PR, no Copilot review, or no issues, say so and stop.

### Step 2: Report and Fix

Report the validation outcome first: how many findings Copilot raised, how many survived, and what was dismissed with the reason.

Then fix every **CRITICAL, HIGH, and MEDIUM** issue that survived validation. Skip LOW unless the user asks for it, and skip everything the validator marked INVALID.

For each fix:
- Read the surrounding code before changing it
- Follow existing conventions in the file
- Do not refactor adjacent code or bundle in unrelated improvements
- Add a regression test where the project has a test suite and a targeted test fits

If a surviving issue turns out to be wrong once you are in the code, say so and skip it rather than implementing a change you do not believe in — the validator reads code too, but you are closer to it.

### Step 3: Summarize

Report what you fixed, what you skipped and why, and anything left for the user to decide. Do not commit or push unless the user asks — use `/rc-toolkit:commit-push` for that.

## Rules

- **Latest review only** — `/rc-toolkit:get-copilot-review` enforces this; do not merge in findings from earlier Copilot runs.
- **Fetch already includes validation** — `get-copilot-review` validates as its final step, so do not run a second validation pass. Just consume its VALID/INVALID split.
- **Never fix a finding that failed validation.** The validator read the code and explained the dismissal. Re-litigating it wastes a change and often makes correct code worse.
- **Use a subagent for the fetch** (Step 1) so its validated results return to you for the fix decision.
