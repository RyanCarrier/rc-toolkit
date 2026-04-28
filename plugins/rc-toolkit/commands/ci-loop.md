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
- If the most recent run **failed**, go to Step 3.

### Step 2: Wait for CI

Poll CI status every 60 seconds until it completes:

```bash
gh run watch <run-id> --exit-status 2>&1 || true
```

- If it **passed**, report success and stop.
- If it **failed**, go to Step 3.

### Step 3: Fetch Failure Details

Get the failure details using the get-ci-failures command:

```
Skill(skill="rc-toolkit:get-ci-failures")
```

### Step 4: Evaluate Failures

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

### Step 5: Fix the Issues

Read the relevant source code and apply fixes for each fixable failure. Follow existing code conventions. Do not refactor surrounding code or add unrelated changes.

### Step 6: Run Pre-Commit Checks

After all fixes are applied, run pre-commit checks.

**First, check for a pre-commit skill or command in the project.** Search available skills and commands (e.g., look for skills matching "pre-commit", "lint", "check", or "format" in the plugin/skill listings). If one exists, invoke it — it knows the project's specific checks and is always preferred.

**Only if no pre-commit skill/command exists**, fall back to inferring from project tooling. Detect the project's tooling and run the appropriate commands. Look for:

- `npm run lint` / `npm run check` / `npm run typecheck` / `npm run format`
- `make lint` / `make check` / `make fmt`
- `cargo fmt` / `cargo check` / `cargo clippy`
- `go fmt` / `go vet` / `golangci-lint run`
- `ruff check` / `ruff format` / `mypy`

Fix any issues surfaced before proceeding.

### Step 7: Commit and Push

Stage only the files changed by the fixes. Commit with a message referencing the CI failure. Push to the current branch.

```bash
git add <changed-files>
git commit -m "<descriptive message referencing the CI fix>"
git push
```

### Step 8: Loop

Go back to Step 1. The push will trigger a new CI run.

## Rules

- Maximum **5 iterations** to avoid infinite loops.
- If an iteration fixes zero issues or the same failure recurs after a fix attempt, stop and report the stall to the user.
- Do not attempt to fix failures outside the scope of this branch's changes.
- Do not modify CI configuration files (workflow YAML, Jenkinsfile, etc.) unless the failure is clearly caused by a change in this branch.
- When stopping due to an unfixable issue, clearly explain what happened, what the blocker is, and what action the user or another team needs to take.
