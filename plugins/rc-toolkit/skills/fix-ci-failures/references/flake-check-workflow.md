# Temporary flake-check workflow

Templates and rules for `.github/workflows/flake_check.yml`, the throwaway workflow Phase 2 adds to repeat one failing job N times. It exists on the fix branch only, in its own commit, and is reverted in Phase 7 before the PR merges.

## Locate the job definition

Start from the workflow that failed and follow the call graph in `.claude/ci-context.md`:

- The failing job's entry has `uses: ./.github/workflows/<child>.yml` → **Variant A** (call the same reusable workflow).
- The entry has `steps:` → **Variant B** (copy the job).
- The entry calls a reusable workflow that itself defines the job inline → Variant B on the child workflow's job.

Record the exact `with:` inputs the parent passes and any matrix the parent fans out over; both must be pinned to the failing variant.

## Variant A: job calls a reusable workflow

```yaml
# TEMPORARY flake-check workflow, added by rc-toolkit:fix-ci-failures.
# Repeats the job under investigation to prove flaky vs genuine and to
# validate the fix. Revert this file before merging the branch.
name: Flake check (temporary)

on:
  push:
    branches:
      - fix/<branch-name>   # exact current branch name, slashes included

concurrency:
  group: flake-check-${{ github.ref_name }}
  cancel-in-progress: true

jobs:
  repeat_<job>:
    strategy:
      fail-fast: false
      max-parallel: 2               # max_parallel_default from ci-context.md
      matrix:
        attempt: [1, 2, 3, 4, 5]    # attempts_default from ci-context.md
    name: attempt ${{ matrix.attempt }}
    uses: ./.github/workflows/<child>.yml
    with:
      # copy every input exactly as the parent passes it;
      # replace parent matrix expressions with the failing variant's literal value
      runs-on: <value>
    secrets: inherit                # only if the parent passes secrets
```

## Variant B: inline job

Copy the job definition into the temporary workflow, then:

1. Pin its matrix to the failing variant (for example `shard: [3]`), keeping `strategy.matrix` so the shard expressions still resolve.
2. Add `attempt: [1, …, N]` as a matrix dimension and `fail-fast: false`; set `max-parallel`.
3. Replace every `${{ inputs.* }}` expression with the literal value the parent passed.
4. Keep `uses: ./.github/…` composite-action references as they are; they resolve from the branch.
5. Rename the job `repeat_<job>` and set `name: attempt ${{ matrix.attempt }}` so runs read clearly in `gh run view`.

```yaml
jobs:
  repeat_<job>:
    runs-on: <same labels as the original>
    timeout-minutes: <same as the original>
    strategy:
      fail-fast: false
      max-parallel: 2
      matrix:
        attempt: [1, 2, 3, 4, 5]
        shard: [3]                  # pinned to the failing variant
    name: attempt ${{ matrix.attempt }}
    steps:
      # …copied verbatim, with inputs.* replaced by literals
```

## Neutralise in-job retries

A retry wrapper (`nick-fields/retry`, a shell loop, a test runner's `--retries`) turns a flake into a pass, so an unmodified copy can report 5/5 green while every first attempt failed.

- **Variant B**: set the wrapper's attempts to 1 (`max_attempts: 1`, `--retries 0`, or equivalent) in the copied job. The baseline must see raw first-attempt behaviour.
- **Variant A**: the wrapper cannot be changed without editing the reusable workflow. Download each attempt's log into `log_dir` and Grep for the wrapper's marker (`Attempt` for `nick-fields/retry`); a pass with a logged retry is a hidden failure and counts against the job.

Apply the same check in Phase 6: a fix is validated only when no attempt needed a retry.

## Sizing

| Job | Attempts | `max-parallel` |
|---|---|---|
| Up to about 20 minutes, hosted runner | `attempts_default` (5) | `max_parallel_default` (2) |
| Listed under Heavy jobs (emulators, simulators, macOS, > 30 min) | `attempts_heavy` (3) | `max_parallel_heavy` (1) |

Never repeat a suite workflow (one that fans out to many jobs); repeat the single job that failed. If a baseline is inconclusive, raise the attempt count rather than repeating a wider scope.

## Concurrency and triggers

- Trigger on `push` to the exact fix branch name only, so the workflow never runs anywhere else.
- Use a dedicated concurrency group (`flake-check-${{ github.ref_name }}`) so the repeat run neither cancels nor is cancelled by the repository's normal push workflows, which keep running alongside it.
- On self-hosted runners, keep `max-parallel` low; the point is a clean signal, not speed.

## Watching

```bash
gh run list --workflow flake_check.yml --limit 5
gh run watch <run_id> --exit-status
gh run view <run_id> --json jobs --jq '.jobs[] | {name, conclusion}'
```

Set the watch timeout to at least twice the job's `timeout-minutes` and never cancel a run mid-flight.

## Revert checklist

1. `git revert --no-edit <flake-workflow-sha>` — a single revert, because the workflow was its own commit.
2. `git diff <default-branch>...HEAD --name-only` must not list `.github/workflows/flake_check.yml`.
3. If a later commit touched the file (it should not have), delete it by hand and commit.
4. Push, wait for the normal CI run, and only then post the PR comment.
