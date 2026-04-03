---
description: Fetch failing jobs, test errors, and stack traces from the most recent failed GitHub Actions run
model: sonnet
context: none
allowed-tools: Bash(gh run *), Bash(gh run:*), Bash(gh run list:*), Bash(gh api:*), Bash(git branch:*), Bash(mkdir:*), Bash(ls:*), Bash(find:*), Bash(rm:*), Bash(cat:*), Bash(unzip:*), Bash(tree:*), Bash(cd tmp:*), Read
---

# Get CI Failures

Analyze the most recent failing CI run on the current branch and provide a structured summary.

## Current State

**Branch:** !`git branch --show-current`

## Instructions

1. **Get recent CI runs** for this branch:

   ```bash
   gh run list --branch $(git branch --show-current) --limit 10 --json databaseId,status,conclusion,name,createdAt,event
   ```

2. **Find the most recent failed run** (conclusion: "failure"). If no failures exist, report "No failed CI runs found" and stop.

3. **Get failed jobs** from that run:

   ```bash
   gh run view <run_id> --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name, conclusion, steps}'
   ```

4. **Get detailed logs** for each failed job:

   ```bash
   gh run view <run_id> --log-failed
   ```

5. **Download failure artifacts** (only if logs indicate artifacts were captured):

   First check if the failed test logs mention capturing artifacts (screenshots, reports, etc.).

   If artifacts were mentioned in the logs:

   ```bash
   rm -rf tmp && mkdir -p tmp
   gh run download <run_id> --dir tmp 2>/dev/null || echo "No artifacts available"
   ```

   If no artifacts were mentioned, skip this step entirely.

6. **Parse and deduplicate test failures:**

   - Look for markers: `FAILED`, `Error:`, assertion failures
   - Tests may retry — report each unique failing test only once

7. **Extract stack traces for each failure (REQUIRED):**

   - For each failed test, find the stack trace that follows the error
   - Look for patterns like:
     - `Expected:` / `Actual:` blocks (matcher failures)
     - Numbered stack frames (`#0`, `#1`, `#2`, etc.)
     - File paths with line numbers (e.g., `file.py:123`, `file.ts:45:12`)
     - Language-specific trace patterns (tracebacks, at lines, etc.)
   - Include 15-30 lines of the stack trace, focusing on:
     - The assertion/error message
     - Stack frames from the project code (not framework internals)
     - The test file and line where failure occurred
   - Do NOT skip stack traces - they are essential for debugging

8. **Output structured summary** with:
   - Run ID and timestamp
   - List of failed jobs
   - Deduplicated failed tests with file paths and error messages
   - **Full stack traces** for each failure (required, not optional)
   - Paths to downloaded artifacts in tmp/ (if any)
   - Suggested next steps

## Output Format

```
## CI Failure Summary - Branch: {branch}

### Failed Run: #{run_id} ({timestamp})

### Failed Jobs:
1. {job_name}
2. {job_name}

### Failed Tests (deduplicated):

#### {job_name}

**Test:** `{test_name}`
**File:** `{file_path}:{line_number}`

**Error:**
```
{error_message}
```

**Stack Trace:**
```
{full_stack_trace_15_30_lines}
```

### Artifacts: (only if downloaded)
- tmp/{artifact_name}/{file}

### Next Steps:
1. Review artifacts at tmp/... (if applicable)
2. Check test at {file_path}:{line}
```

Focus on what failed and why. Stack traces are essential - always include them.
