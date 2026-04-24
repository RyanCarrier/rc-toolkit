# CI Troubleshooting Reference

Common CI failure patterns and resolution strategies for the auto-branch workflow.

## Fetching CI Failure Details

```bash
# Get the latest failed run ID
RUN_ID=$(gh run list --branch $(git branch --show-current) --status failure --limit 1 --json databaseId -q '.[0].databaseId')

# View failed log output
gh run view "$RUN_ID" --log-failed

# List all checks on the PR
gh pr checks $(gh pr view --json number -q .number)
```

## Common Failure Patterns

### Lint/Format Failures
- **Symptom:** CI fails on lint or format check
- **Fix:** Run the project's formatter locally (`npm run format`, `cargo fmt`, `black .`, etc.), commit, and push
- **Prevention:** Always run lint/format in Phase 5 before creating the PR

### Test Failures
- **Symptom:** Tests pass locally but fail in CI
- **Common causes:**
  - Environment differences (Node version, OS, timezone)
  - Missing environment variables or secrets
  - Race conditions in async tests
  - Hardcoded paths or ports
- **Fix:** Read the failing test output, reproduce if possible, fix the test or the code

### Type Check Failures
- **Symptom:** TypeScript, mypy, or similar type checker fails
- **Fix:** Run the type checker locally, fix type errors, commit and push
- **Prevention:** Run type checks in Phase 5

### Build Failures
- **Symptom:** Compilation or build step fails
- **Common causes:**
  - Missing imports or dependencies
  - Syntax errors missed by editor
  - Incompatible dependency versions
- **Fix:** Run the build locally, fix errors, commit and push

### Dependency Issues
- **Symptom:** `npm install`, `pip install`, or similar fails
- **Common causes:**
  - Lock file out of sync with package manifest
  - Removed or yanked package version
  - Private registry auth issues (not fixable from code)
- **Fix:** Update lock file (`npm install`, `pip freeze`), commit and push

### Permission/Auth Failures
- **Symptom:** CI can't access secrets, registries, or APIs
- **Not fixable from code** — report to user with specific error details
- **Note:** These are infrastructure issues, not code issues

## Iteration Strategy

1. Fix the most specific/obvious failure first
2. Push and let CI re-run — don't try to fix everything at once
3. If the same test fails with a different error after a fix, the original fix may have been partial
4. After 3 failed attempts, report to user — the issue may require manual intervention or infrastructure changes
