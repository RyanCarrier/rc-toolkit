---
description: Split a PR into logical sections and review each independently with focused subagents
model: opus
context: none
allowed-tools: Agent, Skill, Bash(git *), Bash(gh pr view:*)
argument-hint: [single] [sections: "area1:file1,file2 | area2:file3,file4"]
---

# Breakdown PR Review

You are an orchestrator that splits a PR into logical sections and reviews each section independently via subagents. This keeps each review's context small and focused, producing more precise findings than a single broad review.

## Step 1: Detect Base Branch and Get Diff

Run these commands to determine the base branch, current branch, and full diff. Prefer the PR's **actual base branch** so PRs stacked on a non-`main` branch compare correctly; fall back to `main`/`master` when no PR exists yet:

```bash
gh pr view --json baseRefName -q .baseRefName 2>/dev/null || (git rev-parse --verify --quiet origin/main >/dev/null 2>&1 && echo main || (git rev-parse --verify --quiet origin/master >/dev/null 2>&1 && echo master))
```

```bash
git branch --show-current
```

If the current branch IS the base branch, tell the user and stop.

Get the diff with file stats for section planning:

```bash
git diff origin/<BASE_BRANCH>...HEAD --stat
```

Get the full diff:

```bash
git diff origin/<BASE_BRANCH>...HEAD
```

If the diff is empty, tell the user there are no changes to review and stop.

## Step 2: Determine Review Mode

Check `$ARGUMENTS` for flags:

- **`single`** — Use a single focused Claude review per section instead of the full multi-provider review (Claude + Antigravity + Codex). This is faster and spawns fewer subagents.
- **`sections: "..."`** — Manual section override (see Step 3b).

Default (no flags): full multi-provider review per section.

## Step 3: Split into Sections

### Step 3a: Auto-Detection (default)

Analyze the diff stat and full diff to group changed files into **2–6 logical sections**. Use these heuristics:

1. **Directory structure** — Files in the same directory or package often form a logical unit.
2. **Feature cohesion** — Files that work together on the same feature (e.g., a handler + its tests + its types) belong together.
3. **Change type** — Separate infrastructure/config changes from application logic changes.
4. **Review coherence** — Each section should be understandable on its own. A reviewer should not need context from another section to evaluate it.

**Grouping rules:**
- Minimum 2 sections, maximum 6.
- If the PR touches ≤ 3 files, use 2 sections (or 1 if they're all tightly coupled — in that case, just run a single section).
- If a single directory dominates (>70% of changes), split it further by sub-feature or file role.
- Tests should be grouped with the code they test, not in a separate "tests" section.
- Config/CI files can form their own section if there are meaningful changes.

**Output the section plan before proceeding:**

```
## Section Plan

1. **[Section Name]** — [brief description of what this section covers]
   - file1.ts
   - file2.ts

2. **[Section Name]** — [brief description]
   - file3.ts
   - file4.ts

...
```

### Step 3b: Manual Override

If the user provided `sections: "..."`, parse the section definitions. Format:

```
sections: "API handlers:src/api/handler.ts,src/api/routes.ts | Database:src/db/migration.ts,src/db/schema.ts | Frontend:src/components/*.tsx"
```

Pipe `|` separates sections. Each section is `name:file1,file2,...`. Glob patterns are expanded.

## Step 4: Launch Section Review Subagents

For each section, spawn a subagent. **Launch all section subagents in a single message** so they run in parallel.

### Multi-Provider Mode (default)

For each section, the subagent runs all three review providers scoped to its files:

```
Agent(
  description="Review: [Section Name]",
  prompt="You are reviewing a specific section of a PR. The base branch is <BASE_BRANCH>.

## Your Section: [Section Name]
[Section description]

## Files in Your Scope
<LIST OF FILES>

## Instructions

Run three independent reviews of ONLY the files in your scope. Use the Agent tool to spawn all three in a single message (parallel):

### Review 1 — Claude PR Review
Agent(
  description='Claude review: [Section Name]',
  prompt='Review ONLY these files from the PR diff against origin/<BASE_BRANCH>: <FILE_LIST>. Invoke Skill(skill=\"pr-review-toolkit:review-pr\"). Focus your review exclusively on the listed files. Ignore issues in other files. Return the complete review output.'
)

### Review 2 — Codex Review
Agent(
  description='Codex review: [Section Name]',
  prompt='Review ONLY these files: <FILE_LIST>. Run: Skill(skill=\"rc-toolkit:codex-review-pr\"). Focus exclusively on the listed files. Return the complete review output.'
)

### Review 3 — Antigravity Review
Agent(
  description='Antigravity review: [Section Name]',
  prompt='Review ONLY these files: <FILE_LIST>. Run: Skill(skill=\"rc-toolkit:agy-review-pr\"). Focus exclusively on the listed files. Return the complete review output.'
)

After all three return, consolidate their results:
1. Deduplicate issues flagged by multiple reviewers — merge into single entries noting which reviewers agreed.
2. Classify severity: CRITICAL, HIGH, MEDIUM, LOW.
3. Boost confidence for issues flagged by 2+ reviewers.
4. Discard clear false positives and style-only nits.

Return a consolidated section report in this format:

## Section: [Section Name]
**Files:** [list]
**Reviewers:** [which completed successfully]
**Issues found:** [count by severity]

### CRITICAL
- [issue] — file:line — flagged by [reviewers] — [description + suggested fix]

### HIGH
...

### MEDIUM
...

### LOW
...
"
)
```

### Single-Review Mode (when `single` flag is set)

For each section, the subagent runs one focused Claude review:

```
Agent(
  description="Review: [Section Name]",
  prompt="You are a senior engineer performing a focused code review of a specific section of a PR. The base branch is <BASE_BRANCH>.

## Your Section: [Section Name]
[Section description]

## Files in Your Scope
<LIST OF FILES>

## Instructions

Get the diff for ONLY your files:
git diff origin/<BASE_BRANCH>...HEAD -- <FILE_LIST_SPACE_SEPARATED>

Read surrounding code for context as needed using the Read tool.

Review for:
1. Bugs & logic errors
2. Security concerns
3. Performance issues
4. Error handling gaps
5. Architectural issues
6. Unintended side effects

Classify each issue:
- CRITICAL: Security vulnerabilities, data loss, system-breaking bugs
- HIGH: Bugs causing incorrect behavior, resource leaks, major architectural issues
- MEDIUM: Missing validation, edge cases, performance concerns
- LOW: Minor improvements

Return your findings in this format:

## Section: [Section Name]
**Files:** [list]
**Issues found:** [count by severity]

### CRITICAL
- file:line — [description + suggested fix]

### HIGH
...

### MEDIUM
...

### LOW
...
"
)
```

## Step 5: Consolidate All Sections

Once all section subagents return:

1. **Collect** all section reports.
2. **Check for cross-section issues** — Look for problems that span sections (e.g., an API change in one section that breaks a consumer in another section). Flag these explicitly.
3. **Produce a unified report:**

```
## Breakdown PR Review Summary

**Mode:** [multi-provider / single]
**Sections reviewed:** [count]
**Total issues:** [count by severity across all sections]

---

### Section 1: [Name]
[Section report from subagent]

### Section 2: [Name]
[Section report from subagent]

...

---

### Cross-Section Issues
[Issues that span multiple sections, if any]

### Overall Recommendations
[merge-ready / needs-fixes / needs-rework]
[Specific action items]
```

## Step 6: Validate Results

After outputting the consolidated report, run the validate-review command to filter out false positives:

```
Skill(skill="rc-toolkit:validate-review")
```

## Rules

- **Orchestrate, don't review.** Do NOT perform any review logic yourself. All reviewing happens in subagents.
- **Parallel execution.** All section subagents MUST be launched in a single message.
- **Scope enforcement.** Each subagent reviews ONLY its assigned files. This is the entire point of the breakdown approach.
- **No silent drops.** Every section must appear in the final report, even if clean.
- **Cross-section awareness.** After collecting results, check for issues that span section boundaries — this is the one thing individual section reviewers cannot catch.
