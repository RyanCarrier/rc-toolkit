---
name: fix-ci-failures
description: This skill should be used when the user asks to "fix CI failures", "fix flaky CI", "hunt down CI flakes", "fix the consistently failing jobs", "why does CI keep failing", "is this test flaky or broken", or when the same CI job fails across multiple recent runs or branches. Surveys recent GitHub Actions runs, adds a temporary repeat-run workflow to prove each failure flaky or genuine, reproduces and fixes the cause, validates on CI, reverts the temporary workflow, and records what it learned in the repository's `.claude/ci-context.md`.
---

# Fix CI Failures

Find CI jobs that fail consistently, prove whether each is flaky or genuinely broken, fix the cause, verify the fix with repeated CI runs, then clean up and record what was learned.

Work through the phases in order. Give the user a one-line status update at each phase boundary. If the user passed a job name or run id, narrow every phase to it.

## The context file

Repository-specific knowledge lives in `.claude/ci-context.md`, committed to the repository. It holds two kinds of content:

- **Structural** — test workflow names, the reusable-workflow call graph, retry wrappers, runners, local reproduction commands, pre-commit checks. Derivable from the repository; generated once in Phase 0 and corrected by hand.
- **Signatures** — known failure patterns with their verdict (flaky or genuine), cause, and response. Earned, not derivable; appended by Phase 7 every time this skill resolves a failure.

Read the whole file before Phase 1 and treat it as the source of truth over the defaults in this skill. It uses the plain `.md` suffix rather than `.local.md` deliberately: flake signatures are team knowledge and belong in git.

## Critical rules

1. Do not use `$()` command substitution. Fetch a value with one command, then paste it into the next.
2. Download CI logs once into the log directory (`log_dir` in the context file, default `tmp/ci-logs/`), then analyze with Grep and Read. Never pipe or re-fetch logs.
3. `conclusion: cancelled` is not a failure. Concurrency-cancelled jobs (a check finishing in seconds, jobs at 0s) show as "fail" in `gh pr checks`. Count a job as failing only when `conclusion == "failure"`.
4. The temporary workflow must be reverted before the PR merges. Merging is the user's call, never this skill's.
5. Never cancel a CI run mid-flight. Set watch timeouts to at least twice the job's `timeout-minutes`.
6. Keep every change scoped to the failure under investigation. Do not refactor around it.

## Phase 0: Load or bootstrap context

1. Read `.claude/ci-context.md`.
2. If it is missing, build it: follow the discovery steps in `references/ci-context.md`, write the draft, and show the user a short summary of what was found — workflow names, the repro table, and pre-commit commands — for a quick sanity check. Continue after their reply. Do not block on a perfect file; an empty Known signatures section is expected.
3. If the user passed `--init` and the file exists, regenerate the structural sections and keep Known signatures untouched.
4. If the file exists but lacks a piece this run needs (for example, no repro command for the failing job), discover just that piece and add it in Phase 7.

## Phase 1: Survey recent runs

Goal: a failure tally per job across the default branch and active branches.

1. List recent runs — the `attempt` field marks re-runs:

   ```bash
   gh run list --branch <default-branch> --limit 15 --json databaseId,conclusion,workflowName,headBranch,headSha,attempt,createdAt,event
   gh run list --limit 40 --json databaseId,conclusion,workflowName,headBranch,headSha,attempt,createdAt,event
   ```

   Keep only the test workflows named in the context file; drop the workflows it lists as ignored.

2. For each run with `conclusion: failure`, list its failing jobs:

   ```bash
   gh run view <run_id> --json jobs --jq '.jobs[] | select(.conclusion == "failure") | .name'
   ```

3. Tally job name × failure count × branches and classify:
   - **Consistent** — fails in all or nearly all recent runs, usually on the default branch too. Likely genuine.
   - **Intermittent** — fails in some runs, or `attempt > 1` passed where attempt 1 failed. Likely flaky.

4. Report the tally. Target the consistent failures plus any flake the user asked about. A failure that appears only on someone else's feature branch and never on the default branch is reported, not fixed there.

5. For each targeted job, download the failed log of one recent run and match its error against Known signatures:

   ```bash
   mkdir -p <log_dir>
   gh run view <run_id> --log-failed > <log_dir>/<run_id>.log
   ```

   A matching signature supplies the verdict and response. When the response is "re-run" and the user did not ask for the flake to be fixed, report that and skip the job; otherwise carry the signature's cause into Phases 2–5 as the working hypothesis.

## Phase 2: Baseline with a temporary repeat-run workflow

Goal: N runs of only the failing job. The baseline separates flaky from genuine, and the same workflow later validates the fix.

1. Work on a fix branch (`fix/<slug>`), never the default branch.
2. Find how the failing job is defined using the call graph in the context file: a job either calls a reusable workflow or is defined inline.
3. Create `.github/workflows/flake_check.yml` that repeats only that job, following `references/flake-check-workflow.md` — it covers both variants, matrix pinning, the concurrency group, and how to neutralise in-job retry wrappers so the baseline cannot be masked.
4. Size the matrix from the context file: `attempts_default` / `max_parallel_default` for ordinary jobs, `attempts_heavy` / `max_parallel_heavy` for jobs listed under Heavy jobs. Never repeat a whole suite workflow; that multiplies every job inside it.
5. Commit the workflow as its own commit (`ci: add temporary flake-check workflow`) so the later revert is a single `git revert`. Push, then watch:

   ```bash
   gh run list --workflow flake_check.yml --limit 5
   gh run watch <run_id> --exit-status
   ```

## Phase 3: Read the baseline

- **All attempts fail with the same error** — genuine. Continue to Phase 4.
- **Mixed pass and fail** — flaky. Skip to Phase 5, expecting a timing or ordering root cause.
- **All attempts pass** — either an in-job retry masked the flake (download the logs and Grep for the retry wrapper's attempt marker, usually `Attempt`), or the failure needs conditions the repeat run lacks (sharding order, a warm full-suite cache, a specific runner). Broaden the survey or raise the attempt count before concluding anything.

Flaky does not mean unfixable. When the user invoked this skill on a known flake, the goal is to remove the race, not to re-run until green.

## Phase 4: Reproduce locally

Reproduce genuine failures locally before touching code. Use `rc-toolkit:get-ci-failures` first when the failing test and stack trace are not already known.

1. Look up the failing job in the Local reproduction table of the context file and run that command.
2. If the job is not in the table, discover a command — a `scripts/` entry, a project skill or command, or a test invocation in CLAUDE.md — and record it for Phase 7.
3. Respect the Platform limits noted in the context file. A job that needs an OS this machine lacks is diagnosed from CI logs and validated through the flake-check workflow alone.
4. For a flake, run the local command in a loop (5 to 10 times) to catch the race. Some failures reproduce only under CI sharding or only in isolation, so a single green local run is weak evidence.

## Phase 5: Diagnose, plan, fix, verify locally

1. Pull full stack traces and failure artifacts from the downloaded logs.
2. Read the failing test and the code under test. Identify the root cause, not the symptom. For flakes, look for missing awaits, lifecycle races, unsettled animations, shared mutable state between tests, and off-screen interactions.
3. State the diagnosis and the planned fix in one short message before implementing.
4. Implement the fix, then rerun the Phase 4 reproduction. Rerun a flake fix several times.
5. Run the pre-commit checks listed in the context file. Prefer a project pre-commit skill or command when one exists.

## Phase 6: PR and CI validation

1. Commit the fix and push. Open a PR if none exists (`gh pr create`) describing the root cause and the fix. State in the PR body that `flake_check.yml` is temporary and will be reverted before merge.
2. Wait for both the normal PR workflow and the flake-check workflow with `gh run watch`.
3. Success means normal CI is green AND every flake-check attempt passes with no hidden retry attempts in the logs.
4. If anything still fails, return to Phase 5 with the new logs.

## Phase 7: Revert, record, report

1. Revert the temporary workflow commit and confirm it is gone:

   ```bash
   git revert --no-edit <flake-workflow-sha>
   git diff <default-branch>...HEAD --name-only
   ```

   If later commits touched `flake_check.yml` (they should not), delete the file manually instead.

2. Record what was learned in `.claude/ci-context.md`:
   - Append one entry to Known signatures in the format given in `references/ci-context.md`: job, error pattern, verdict, cause, response, evidence run URL, date.
   - Add any repro command or structural fact discovered during this run to its section.
   - Update `updated:` in the frontmatter.

   Commit this together with the revert (`ci: revert flake-check workflow; record <job> signature`) and push.

3. Wait for the final normal CI run to pass.
4. Comment on the PR with the root cause, the fix, the flake-check evidence (for example "base_e2e passed 5/5 repeats in run <url>"), and a note that the temporary workflow was added and reverted.
5. Stop. Merging is the user's call.

## Relationship to other rc-toolkit workflows

- `rc-toolkit:get-ci-failures` extracts failing tests and stack traces from one run. Use it inside Phases 4 and 5; it does not survey across runs or prove flakiness.
- `rc-toolkit:ci-loop` fixes deterministic failures introduced by the current branch and stops when it meets a flake. This skill is where it hands off: recurring flakes and failures that predate the branch.
- `rc-toolkit:auto-branch` delegates CI repair to `ci-loop`; invoke this skill separately when a flake blocks it.

## Additional Resources

### Reference Files

- **`references/ci-context.md`** — The `.claude/ci-context.md` template, section by section, with the discovery commands that fill each structural section and the Known signatures entry format.
- **`references/flake-check-workflow.md`** — Templates for the temporary repeat-run workflow (reusable-workflow and inline-job variants), sizing rules, retry-wrapper handling, and the revert checklist.
