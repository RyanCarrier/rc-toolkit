# The `.claude/ci-context.md` file

Per-repository knowledge for the fix-ci-failures skill: the template, how to fill each section during Phase 0 bootstrap, and the format for the entries Phase 7 appends.

## Why a committed file

A generic skill cannot know a repository's workflow layout or which errors are known flakes, and that knowledge is what makes a CI hunt fast. Keeping it in a file the skill reads — rather than in the skill — lets one skill serve every repository while each repository stays as sharp as its history. The file uses the plain `.md` suffix, not `.local.md`, because flake signatures are team knowledge: commit it, review changes to it in PRs, and let every teammate benefit from each recorded verdict.

The structural sections are derivable from the repository and generated once. The Known signatures section is earned and grows with use. Keep both short; the file is read in full at the start of every run.

## Template

```markdown
---
log_dir: tmp/ci-logs
attempts_default: 5
attempts_heavy: 3
max_parallel_default: 2
max_parallel_heavy: 1
updated: YYYY-MM-DD
---

# CI context

Read by the `rc-toolkit:fix-ci-failures` skill. Structural sections were generated on <date>; Known signatures are appended as failures are resolved. Edit freely.

## Workflows

Test workflows (survey these):

| File | Display name | Trigger |
|---|---|---|
| `<file>.yml` | <name: value> | `pull_request` / push to `<branches>` |

Ignore: <deploy, release, dependency-update, metrics, and other non-test workflows>.

Call graph:

- `<parent>.yml` → `<child>.yml`, `<child>.yml`, inline job `<name>`

Composite actions: `<path>` (resolve from the branch, so copied jobs keep working).

Retry wrappers: `<action>` wraps the test step in `<files>`; grep logs for `<marker>` to find masked first attempts.

Runners: <hosted or self-hosted; labels; concurrency notes>.

## Heavy jobs

Use `attempts_heavy` / `max_parallel_heavy` for: <jobs>, with their `timeout-minutes`.

Expected durations: <from project docs, if any>.

## Local reproduction

| Failing job | Command |
|---|---|
| `<workflow> / <job>` | `<command>` — <notes on order, isolation, prerequisites> |

Platform limits: <jobs that need an OS this machine may lack>.

## Pre-commit checks

<project skill or command to prefer, then the equivalent shell commands>

## Known signatures

<empty at bootstrap — entries are appended by Phase 7; see the format below>
```

## Filling each section

Run the discovery below during Phase 0. Every command reads the repository; none needs `$()`. Record findings tersely — a reader should be able to scan the whole file in a minute.

### Frontmatter knobs

| Key | Meaning | Default |
|---|---|---|
| `log_dir` | Where CI logs are downloaded once, then analysed with Grep and Read | `tmp/ci-logs` |
| `attempts_default` / `max_parallel_default` | Flake-check matrix size for jobs up to about 20 minutes | 5 / 2 |
| `attempts_heavy` / `max_parallel_heavy` | Matrix size for jobs listed under Heavy jobs | 3 / 1 |
| `updated` | Date of the last edit; bump it in Phase 7 | — |

Lower `max_parallel_*` on self-hosted runners so the repeat run does not starve other work.

### Workflows

```bash
ls .github/workflows/
grep -m1 '^name:' .github/workflows/*.yml
grep -n 'uses: ./.github/workflows/' .github/workflows/*.yml
grep -n -B1 -A4 -E 'nick-fields/retry|max_attempts|retries' .github/workflows/*.yml
grep -h 'runs-on:' .github/workflows/*.yml | sort | uniq -c
```

For each candidate test workflow, read its `on:` block (`sed -n '/^on:/,/^[a-z]/p' <file>`) to record the trigger. A workflow whose name or trigger says deploy, release, publish, dependency, coverage, metrics, or visualization goes on the ignore list. Follow `uses: ./.github/workflows/…` lines to draw the call graph; note jobs defined inline (a `jobs:` entry with `steps:` rather than `uses:`), since they are copied rather than called in `flake_check.yml`. A `uses:` path with no `.yml` suffix is a composite action.

### Heavy jobs

```bash
grep -n 'timeout-minutes' .github/workflows/*.yml
```

List jobs with large timeouts, emulator or simulator boots, or macOS runners. Copy any expected-duration guidance from CLAUDE.md, AGENTS.md, or a contributing guide.

### Local reproduction

Map every test job to a local command. Look, in order, at:

1. Project skills and commands (`.claude/skills/`, `.claude/commands/`) named for tests, e2e, integration, or a platform.
2. `scripts/` entries with test, e2e, or screenshot in the name.
3. Test commands in CLAUDE.md, AGENTS.md, README, `package.json` scripts, `Makefile`, `justfile`, or `pyproject.toml`.
4. The workflow's own `run:` step — the last resort, adapted for a local machine.

Note whether a job shards tests (`--shard-index`, `--split`, matrix `shard:`), since sharding changes test order and a failure may only reproduce under the same order.

### Platform limits

Compare `uname -s` with the platforms the test jobs run on. Record jobs that cannot run on this machine (typically iOS and macOS on a Linux host) so Phase 4 diagnoses them from logs instead of attempting a reproduction.

### Pre-commit checks

Look for a project skill or command named pre-commit, lint, check, or format first; it knows the project's exact checks. Otherwise record the commands from CLAUDE.md, AGENTS.md, `.pre-commit-config.yaml`, `package.json` scripts, or the Makefile.

## Known signatures entry format

Append one bullet per resolved failure:

```markdown
- **<workflow> / <job>** — `<distinctive error text or pattern>` → **flaky** | **genuine**. Cause: <root cause in one clause>. Response: <re-run | fixed in #<PR> | what to change>. Evidence: <flake-check run URL> (<YYYY-MM-DD>)
```

Guidance:

- Quote the error text a future Grep would match, not a paraphrase.
- A single job can have several signatures with different verdicts; keep them as separate bullets.
- When a recorded flake is later fixed for good, keep the entry and change its Response to `fixed in #<PR>` so a recurrence is recognised as a regression rather than rediscovered as a flake.
- Prune entries whose job no longer exists.

## Maintaining the file

- Phase 7 appends signatures and adds any repro command or structural fact discovered during the run.
- Re-run Phase 0 discovery with `--init` after a CI restructure; it regenerates the structural sections and preserves Known signatures.
- Humans edit freely; the skill treats the file as the source of truth over its own defaults.
