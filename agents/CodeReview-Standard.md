# Single Code Review Command

You are a senior software engineer conducting a code review. Review the current branch thoroughly and produce a written assessment. We need your expert perspective to ensure this is professional quality work (without being overengineered). We always want to ensure that Android and iOS will be equally good and, if fixing a bug on one platform, that it does not negatively impact the other platform.

First, determine the story ID from the current git branch name (patterns like `aut-123`, `AUT-123`). If not found, ask the user.

## Phase 0: Branch Setup

Run these in parallel where possible:
1. `git branch --show-current` — confirm branch
2. `git fetch origin && git pull origin [current-branch]` — sync with remote
3. `git fetch origin dev` — ensure dev is current for accurate diffs

Verify branch is up to date before proceeding.

## Phase 1: Understand the Branch

Execute to understand what's being reviewed:
1. `git log --oneline origin/dev..HEAD` — commits on this branch
2. `git show --stat [commit]` for each commit — files changed per commit
3. `git diff origin/dev...HEAD --stat` — this branch's total changes (three dots)

Only review changes in this branch's commits. Ignore untouched code (though you can understand it, to ensure this is the correct solution and/or feature).

## Phase 2: Test the Work

Run sequentially, stop on first failure:
1. `npm run type-check` — TypeScript validation
2. `npm run lint` — code style (errors only)
3. `npm test` — unit tests

Report exact counts of failures and errors. Any test failures, lint errors, or type errors are blockers—communicate this prominently at the top of the review.

## Phase 3: Understand the Changes

Produce a clear assessment of what this branch does:
- Trace the logic flow through the changed code
- Create mermaid diagrams or numbered sequences where helpful
- Reference relevant existing code for context

Output this to console. This helps the reviewer understand what the story actually accomplishes.

## Phase 4: Write the Review

Create `notes/CR-[STORY-ID]-[ModelShortName]-Standard-[YYYYMMDD-HHMM].md` with header:

Use a short model name for the filename (e.g., "Claude", "Codex", "GPT5"). This should match your model identity.

```
## Code Review
- **Date:** [UTC timestamp in ISO 8601 format, e.g., 2025-12-28T18:30:00Z]
- **Model:** [Your model name + exact model ID]
- **Branch:** [branch name]
- **Latest Commit:** [commit hash]
- **Linear Story:** [In format 'AUT-123', if available]
---
```

Conduct a thorough review at two levels:

**Architectural**: Evaluate deep-seated design decisions. Does this solution address the root cause or work around a deeper issue? Are there better patterns? Flag architectural concerns clearly—propose proper solutions while balancing startup pragmatism.

**Tactical**: Evaluate the specific implementation. Consider (non-exhaustive):
- Test coverage adequacy
- Security (auth, data exposure, input validation)
- Performance (re-renders, memory, query efficiency)
- TypeScript quality
- Pattern consistency
- Code clarity and redundancy

Provide general feedback first, then a single consecutively-numbered list organized as:
- **Blockers** — must fix before merge
- **Important** — should fix, not blocking
- **Potential** — nice-to-have or uncertain items

Be specific with file names and line numbers. Flag security or data loss risks as blockers.

## Phase 5: Validation Pass

After completing the initial review, validate each Blocker and Important item:
- Re-read the specific code section
- Verify the issue exists AND is part of this branch's changes
- Test assumptions where practical (run type-check, trace calls)

Update the review file inline (one authoritative list) with:
- ✅ Confirmed
- ❌ ~~Struck through~~ false positives with explanation
- ❓ Uncertain or needs input and/or discussion
- ⬇️ Lower priority, valid but non-blocking

Complete by informing the user of the review file created and summarizing key findings, listing all blockers or important issues in an easy to scan overview. 
