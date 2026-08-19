---
description: Wait for CI to pass, fix failures, and retry until green or blocked
model: opus
context: none
---

# CI Loop

Poll CI status, fix failures, and repeat until CI passes or the issue requires external action.

## Instructions

### Step 1: Get Current CI Status

Determine the current branch and check CI status:

```bash
git branch --show-current
```

```bash
gh run list --branch $(git branch --show-current) --limit 1 --json status,conclusion,databaseId,workflowName
```

- If **no runs exist**, tell the user and stop.
- If a run is **in progress** or **queued**, go to Step 2.
- If the most recent run **succeeded**, report success and stop.
- If the most recent run was **cancelled**, go to Step 3.
- If the most recent run **failed**, go to Step 4.

### Step 2: Wait for CI

Poll CI status every 60 seconds until it completes:

```bash
gh run watch <run-id> --exit-status 2>&1 || true
```

Then check the conclusion — `gh run watch` exits non-zero for both failures and cancellations:

```bash
gh run view <run-id> --json conclusion
```

- If it **passed**, report success and stop.
- If it was **cancelled**, go to Step 3.
- If it **failed**, go to Step 4.

### Step 3: Triage a Cancelled Run

A cancelled run has two common causes. Determine which one applies before acting:

```bash
gh run list --branch $(git branch --show-current) --limit 5 --json status,conclusion,databaseId,workflowName,createdAt
```

**Superseded by a newer run (concurrency cancellation):** A newer run of the same workflow on this branch exists, created at or after the cancellation. The cancelled run's annotations (visible in `gh run view <run-id>`) typically read "Canceling since a higher priority waiting request ... exists". Nothing is wrong — switch to the newer run and go back to Step 1. This does not count as an iteration.

**Cancelled manually:** No newer run of that workflow exists, and/or the annotations show a plain "The run was canceled" message without the concurrency wording. A manual cancel usually means someone saw failures already happening and stopped the run — look for them:

```bash
gh run view <run-id> --json jobs --jq '.jobs[] | select(.conclusion == "failure") | .name'
```

- If jobs **failed before the cancellation**, fetch their logs directly from this run with `gh run view <run-id> --log-failed` (do not use get-ci-failures here — it only matches runs whose conclusion is `failure`, so it will skip this cancelled run), then go to Step 5.
- If **no jobs failed**, the cancellation was a deliberate intervention with nothing broken on record. Report that the run was manually cancelled and stop — do not push or re-trigger over someone's manual cancel.

### Step 4: Fetch Failure Details

Get the failure details using the get-ci-failures command:

```
Skill(skill="rc-toolkit:get-ci-failures")
```

### Step 5: Evaluate Failures

Classify each failure:

- **Fixable:** Lint errors, type errors, test failures caused by code in this branch, formatting issues, build errors from code changes.
- **Not fixable (stop and report):**
  - Flaky infrastructure (network timeouts, registry errors, runner issues)
  - Failures in code outside this branch's changes
  - Permission or secret/credential issues
  - Dependency resolution failures from external registries
  - Issues requiring manual configuration or external service action

If all failures are **not fixable**, report them clearly to the user and stop. Explain what external action is needed.

If a mix exists, fix what is fixable and report what is not.

### Step 6: Fix the Issues

Read the relevant source code and apply fixes for each fixable failure. Follow existing code conventions. Do not refactor surrounding code or add unrelated changes.

### Step 7: Run Pre-Commit Checks

After all fixes are applied, run pre-commit checks.

**First, check for a pre-commit skill or command in the project.** Search available skills and commands (e.g., look for skills matching "pre-commit", "lint", "check", or "format" in the plugin/skill listings). If one exists, invoke it — it knows the project's specific checks and is always preferred.

**Only if no pre-commit skill/command exists**, fall back to inferring from project tooling. Detect the project's tooling and run the appropriate commands. Look for:

- `npm run lint` / `npm run check` / `npm run typecheck` / `npm run format`
- `make lint` / `make check` / `make fmt`
- `cargo fmt` / `cargo check` / `cargo clippy`
- `go fmt` / `go vet` / `golangci-lint run`
- `ruff check` / `ruff format` / `mypy`

Fix any issues surfaced before proceeding.

### Step 8: Commit and Push

Stage only the files changed by the fixes. Commit with a message referencing the CI failure. Push to the current branch.

```bash
git add <changed-files>
git commit -m "<descriptive message referencing the CI fix>"
git push
```

### Step 9: Loop

Go back to Step 1. The push will trigger a new CI run.

## Rules

- Maximum **5 iterations** to avoid infinite loops. Switching to a run that superseded a cancelled one (Step 3) does not count as an iteration.
- Never re-trigger or push over a manually cancelled run that has no failed jobs — treat the cancellation as a deliberate stop signal from a human.
- If an iteration fixes zero issues or the same failure recurs after a fix attempt, stop and report the stall to the user.
- Do not attempt to fix failures outside the scope of this branch's changes.
- Do not modify CI configuration files (workflow YAML, Jenkinsfile, etc.) unless the failure is clearly caused by a change in this branch.
- When stopping due to an unfixable issue, clearly explain what happened, what the blocker is, and what action the user or another team needs to take.
