# Trident Code Review: Nine-Agent Code Review

Run parallel code reviews using Claude, Codex, and Gemini — each provider runs three lenses: Standard, Critical (adversarial), and Evolutionary (exploratory). Output lives in a review pack folder under `notes/`.

**Usage:**
- `/user:trident-code-review` — Review current branch with all nine agents
- `/user:trident-code-review [context]` — Review with additional context: `$ARGUMENTS`

**How to invoke:** a single agent runs this command. The nine reviewers and three synthesizers are that agent's sub-agents and headless bash sessions — they do NOT need their own panes or surfaces. If you're a Review sibling inside a delegator pattern, you invoke `/trident-code-review` from your one surface and the 9+3 run under you.

---

## Critical Rule: READ-ONLY applies to the 9 reviewers and 3 synthesizers

The **nine review agents and three synthesis agents** are strictly read-only. They must ONLY:
- Read existing files (source code, prompt files, related context)
- Write their single designated output file to the review pack folder

They must NEVER:
- Commit or push to git
- Modify any existing files
- Create files outside the review pack folder or the tmp staging directory
- Run destructive commands of any kind

Enforce this in every launch message. Agents that try to commit, modify source files, or take actions beyond writing their review output are violating the contract.

**The caller (the agent that invoked `/trident-code-review`) is NOT read-only.** After the syntheses land, the caller is expected to act on the findings — see "After Synthesis" below.

---

## Architecture

```
Main Agent (Opus 4.6)
├── Git operations (once)
├── Test suite (once)
├── Generate context document
├── Identify related context files for agents
├── Write prompt files for Codex/Gemini (file-reference approach)
├── Launch 9 agents
│   ├── 3x Claude — via Agent tool (subagents)
│   ├── 3x Codex — via Bash (headless CLI)
│   └── 3x Gemini — via Bash (headless CLI)
├── Wait and collect all 9
├── Quality gate — verify output files exist and have substance
├── Launch 4 synthesis Agents in parallel
│   ├── Standard lens (reads 3 standard reviews)
│   ├── Critical lens (reads 3 critical reviews)
│   ├── Evolutionary lens (reads 3 evolutionary reviews)
│   └── Action-ready (reads all 9 originals + context doc; agent-consumable fix plan)
├── Open all 4 synthesis docs
└── Clean up tmp staging directory
```

After all 9 complete, launch 4 synthesis agents in a single parallel batch. Three lens synthesizers each consolidate one lens across the three models; a fourth action-ready synthesizer reads all 9 originals plus the context doc and produces a validated, machine-actionable fix plan. All four run in parallel so total runtime is bounded by the slowest single synthesis, not the sum.

---

## Agent Configuration

| Agent | Type | Lens | Command |
|-------|------|------|---------|
| Claude | Agent | Standard | Agent tool with standard prompt |
| Claude | Agent | Critical | Agent tool with critical prompt |
| Claude | Agent | Evolutionary | Agent tool with evolutionary prompt |
| Codex | Bash | Standard | `env -u CLAUDECODE codex exec --full-auto --skip-git-repo-check "Read {prompt_file}..." 2>&1 \| tee {log}` |
| Codex | Bash | Critical | same pattern |
| Codex | Bash | Evolutionary | same pattern |
| Gemini | Bash | Standard | `gemini -m gemini-3-pro-preview --yolo "Read {prompt_file}..." 2>&1 \| tee {log}` |
| Gemini | Bash | Critical | same pattern |
| Gemini | Bash | Evolutionary | same pattern |

**IMPORTANT:** All prompt files MUST be written inside the workspace (e.g., `notes/.tmp/`) — NOT `/tmp/`. Gemini CLI sandboxes file reads to workspace directories only.

---

## Instructions

### Phase 1: Gather All Context (Main Agent Does This Once)

Run these commands to build the complete context:

```bash
# Branch info
git branch --show-current
git fetch origin dev

# Determine base branch (dev if it exists, otherwise main/master)
git merge-base HEAD origin/dev

# Commits on this branch
git log --oneline origin/dev..HEAD

# Full diff (not just stat)
git diff origin/dev...HEAD

# File change summary
git diff origin/dev...HEAD --stat
```

Derive `REVIEW_ID` from the branch name, including enough path context to prevent collisions:
- `feature/projects/music-fetcher/pipeline` -> `music-fetcher-pipeline`
- `fix/auth-handler` -> `auth-handler`
- `aut-123-add-search` -> `AUT-123`

If the branch name contains a ticket pattern (`aut-123` or `AUT-123`), extract and uppercase it as `STORY_ID`. Otherwise:

- **Lattice repo** (`.lattice/` directory exists): Tell the caller: "This repo uses Lattice but I couldn't determine the task ID from the branch name. Provide the Lattice task ID (run `lattice list --status in_progress` to see active tasks)."
- **Non-Lattice repo**: Derive `REVIEW_ID` from the branch name as shown above. Ask: "No ticket ID found in the branch name. Using `{REVIEW_ID}` as the review namespace — OK?"

Use `REVIEW_ID` throughout (it equals `STORY_ID` when a ticket is found).

### Phase 1b: Identify Related Context

Look for files that would help reviewers ground their feedback:
- Sibling files in changed directories (e.g., `CLAUDE.md`, existing tests, config files)
- Related modules or projects with similar patterns
- Any files referenced or imported by the changed code

Build a `CONTEXT_NOTE` string listing these paths, e.g.:
> "For additional context, you may also read these related files: `projects/music_fetcher/CLAUDE.md`, `projects/movie_fetcher/pipeline.py` (sibling project with same pattern)."

If no relevant context is found, set `CONTEXT_NOTE` to empty.

### Phase 2: Run Test Suite (Main Agent Does This Once)

Detect the project's test runner:

- **If `package.json` exists**: `npm run type-check`, `npm run lint`, `npm test`
- **If `pyproject.toml` exists**: `uv run pytest`, `uv run ruff check src/ tests/`, `uv run ruff format --check src/ tests/`
- **If neither exists or commands fail**: Note which checks were skipped and why. Do not block the review.

Run sequentially, capture all output.

### Phase 3: Generate Context Document

Create workspace temp directory:
```bash
mkdir -p notes/.tmp/trident-{REVIEW_ID}
```

Write `notes/.tmp/trident-{REVIEW_ID}/team-review-context.md` with all gathered information (branch info, commits, test results, file changes, full diff). Same format as team_three_review.

### Phase 4: Build the Three Review Prompts

Create a tmp staging directory (if not already created):
```bash
mkdir -p notes/.tmp/trident-{REVIEW_ID}
```

Generate a timestamp:
```bash
date +%Y%m%d-%H%M
```
Save for report filenames.

**For Codex and Gemini**, use the file-reference approach to avoid shell escaping issues. Write each agent's full prompt to a tmp file rather than passing it inline.

First, concatenate the canonical review prompts with the context document:

```bash
# Standard prompt
cat ~/.claude/agents/CodeReview-Standard.md > notes/.tmp/trident-{REVIEW_ID}/trident-review-standard.md
echo -e "\n\n---\n\n**Additional Context:** $ARGUMENTS\n\n---\n\n# CONTEXT DOCUMENT\n" >> notes/.tmp/trident-{REVIEW_ID}/trident-review-standard.md
cat notes/.tmp/trident-{REVIEW_ID}/team-review-context.md >> notes/.tmp/trident-{REVIEW_ID}/trident-review-standard.md

# Critical prompt
cat ~/.claude/agents/CodeReview-Critical.md > notes/.tmp/trident-{REVIEW_ID}/trident-review-critical.md
echo -e "\n\n---\n\n**Additional Context:** $ARGUMENTS\n\n---\n\n# CONTEXT DOCUMENT\n" >> notes/.tmp/trident-{REVIEW_ID}/trident-review-critical.md
cat notes/.tmp/trident-{REVIEW_ID}/team-review-context.md >> notes/.tmp/trident-{REVIEW_ID}/trident-review-critical.md

# Evolutionary prompt
cat ~/.claude/agents/CodeReview-Evolutionary.md > notes/.tmp/trident-{REVIEW_ID}/trident-review-evolutionary.md
echo -e "\n\n---\n\n**Additional Context:** $ARGUMENTS\n\n---\n\n# CONTEXT DOCUMENT\n" >> notes/.tmp/trident-{REVIEW_ID}/trident-review-evolutionary.md
cat notes/.tmp/trident-{REVIEW_ID}/team-review-context.md >> notes/.tmp/trident-{REVIEW_ID}/trident-review-evolutionary.md
```

Then, write per-agent prompt files for Codex and Gemini (6 total):

```bash
# Example for standard-codex — repeat pattern for all 6 (standard/critical/evolutionary x codex/gemini)
cat > notes/.tmp/trident-{REVIEW_ID}/prompt-standard-codex.md <<'PROMPT_EOF'
Read notes/.tmp/trident-{REVIEW_ID}/trident-review-standard.md and follow the instructions.

**THIS IS A READ-ONLY REVIEW.** Your ONLY output is the review file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.

**OUTPUT:** Write your review to `notes/trident-review-{REVIEW_ID}-pack-{TIMESTAMP}/standard-codex.md`

Use these values: STORY_ID={REVIEW_ID}, MODEL=Codex.
{CONTEXT_NOTE}

Now follow the instructions in the review prompt file.
PROMPT_EOF
```

For Gemini, also copy the prompt framework files into the workspace (Gemini sandboxes reads to the workspace):
```bash
cp ~/.claude/agents/CodeReview-Standard.md notes/.tmp/trident-{REVIEW_ID}/
cp ~/.claude/agents/CodeReview-Critical.md notes/.tmp/trident-{REVIEW_ID}/
cp ~/.claude/agents/CodeReview-Evolutionary.md notes/.tmp/trident-{REVIEW_ID}/
```

For Gemini prompt files, use workspace-local paths for both the framework file and the context document.

### Phase 5: Create Review Pack and Launch All Nine Agents

Create the review pack folder:
```bash
mkdir -p notes/trident-review-{REVIEW_ID}-pack-{TIMESTAMP}
```
Store this path as `PACK_DIR`.

Launch all nine with `run_in_background: true` for Bash agents. Claude agents use the Agent tool (3 calls in a single message).

**Launch message template** (for Claude subagents — Codex/Gemini use their prompt files from Phase 4):

> Read notes/.tmp/trident-{REVIEW_ID}/trident-review-{lens}.md and follow the instructions.
>
> **THIS IS A READ-ONLY REVIEW.** Your ONLY output is the review file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.
>
> **OUTPUT:** Write your review to `{PACK_DIR}/{lens}-claude.md`
>
> Use these values: STORY_ID={REVIEW_ID}, MODEL=Claude.
> {CONTEXT_NOTE}
> Additional context from the user: {ADDITIONAL_NOTES}
>
> Now follow the instructions in the review prompt file.

---

**Claude agents** (3x) — use the **Agent tool** (parallel subagents):

Launch three Agent tool calls in a single message with the launch template, substituting:
- Standard: `lens=standard`
- Critical: `lens=critical`
- Evolutionary: `lens=evolutionary`

---

**Codex agents** (3x) — use Bash with `run_in_background: true`:

**Important:** Use `env -u CLAUDECODE` to strip the environment variable that blocks nested sessions.

Each agent reads its prompt from the file written in Phase 4:

```bash
env -u CLAUDECODE codex exec --full-auto --skip-git-repo-check "Read notes/.tmp/trident-{REVIEW_ID}/prompt-standard-codex.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/codex-standard.log

env -u CLAUDECODE codex exec --full-auto --skip-git-repo-check "Read notes/.tmp/trident-{REVIEW_ID}/prompt-critical-codex.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/codex-critical.log

env -u CLAUDECODE codex exec --full-auto --skip-git-repo-check "Read notes/.tmp/trident-{REVIEW_ID}/prompt-evolutionary-codex.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/codex-evolutionary.log
```

---

**Gemini agents** (3x) — use Bash with `run_in_background: true`:

Each agent reads its prompt from the file written in Phase 4:

```bash
gemini -m gemini-3-pro-preview --yolo "Read notes/.tmp/trident-{REVIEW_ID}/prompt-standard-gemini.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/gemini-standard.log

gemini -m gemini-3-pro-preview --yolo "Read notes/.tmp/trident-{REVIEW_ID}/prompt-critical-gemini.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/gemini-critical.log

gemini -m gemini-3-pro-preview --yolo "Read notes/.tmp/trident-{REVIEW_ID}/prompt-evolutionary-gemini.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/gemini-evolutionary.log
```

---

**Tell the user:**
> "Context prepared. Test results: {type-check: PASS/FAIL, lint: PASS/FAIL, tests: PASS/FAIL}
>
> Launched 9 review agents:
> - Claude (Standard, Critical, Evolutionary)
> - Codex (Standard, Critical, Evolutionary)
> - Gemini (Standard, Critical, Evolutionary)
>
> Review pack: `{PACK_DIR}/`
>
> You can continue working. I'll synthesize when complete."

### Phase 6: Wait, Collect, and Quality Gate

- For Claude agents: the Agent tool calls will return when complete.
- For Codex/Gemini agents: use `TaskOutput` with `block: true` for each background Bash task.

Find review files:
```bash
ls -la {PACK_DIR}/*.md 2>/dev/null
```

**Quality gate:** Verify output files exist and have substance:
```bash
wc -c {PACK_DIR}/*.md
```

- Files over 500 bytes: good, proceed to synthesis.
- Files under 500 bytes: likely failed or empty. Check the corresponding log in `notes/.tmp/trident-{REVIEW_ID}/` and note the gap.
- Missing files: check logs, note which agent failed.

Report any gaps to the user before proceeding to synthesis.

Expected files: `standard-claude.md`, `standard-codex.md`, `standard-gemini.md`, `critical-claude.md`, `critical-codex.md`, `critical-gemini.md`, `evolutionary-claude.md`, `evolutionary-codex.md`, `evolutionary-gemini.md`.

### Phase 7: Four Synthesis Agents (parallel)

Launch **four Agent tool calls in a single message** so they run in parallel. Three synthesize one lens each across the three models; the fourth produces the action-ready validated fix plan directly from the 9 originals plus the context document.

Total wall-clock runtime for this phase is bounded by the slowest single synthesis, not the sum.

**Synthesis-Standard Agent:**
> Read all Standard code reviews for {REVIEW_ID}:
> - `{PACK_DIR}/standard-claude.md`
> - `{PACK_DIR}/standard-codex.md`
> - `{PACK_DIR}/standard-gemini.md`
>
> **THIS IS A READ-ONLY REVIEW.** Your ONLY output is the synthesis file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.
>
> Synthesize into a single document. Focus on:
> 1. Consensus issues — what do 2+ models agree on? (highest confidence)
> 2. Divergent views — where do models disagree? (signal worth examining)
> 3. Unique findings — issues only one model raised
> 4. Consolidated blockers, important items, and suggestions (deduplicated)
>
> Write to: `{PACK_DIR}/synthesis-standard.md`
> Format as numbered lists. Start with executive summary and merge verdict.

**Synthesis-Critical Agent:**
> Read all Critical code reviews for {REVIEW_ID}:
> - `{PACK_DIR}/critical-claude.md`
> - `{PACK_DIR}/critical-codex.md`
> - `{PACK_DIR}/critical-gemini.md`
>
> **THIS IS A READ-ONLY REVIEW.** Your ONLY output is the synthesis file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.
>
> Synthesize into a single document. Focus on:
> 1. Consensus risks — failure modes multiple models identified (highest priority)
> 2. Unique concerns — risks only one model raised (worth investigating)
> 3. The ugly truths — hard messages that recur across models
> 4. Consolidated blockers and production risk assessment
>
> Write to: `{PACK_DIR}/synthesis-critical.md`
> Format as numbered lists. Start with executive summary and production readiness verdict.

**Synthesis-Evolutionary Agent:**
> Read all Evolutionary code reviews for {REVIEW_ID}:
> - `{PACK_DIR}/evolutionary-claude.md`
> - `{PACK_DIR}/evolutionary-codex.md`
> - `{PACK_DIR}/evolutionary-gemini.md`
>
> **THIS IS A READ-ONLY REVIEW.** Your ONLY output is the synthesis file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.
>
> Synthesize into a single document. Focus on:
> 1. Consensus direction — evolution paths multiple models identified
> 2. Best concrete suggestions — most actionable ideas across all three
> 3. Wildest mutations — creative/ambitious ideas worth exploring
> 4. Leverage points and flywheel opportunities
>
> Write to: `{PACK_DIR}/synthesis-evolutionary.md`
> Format as numbered lists. Start with executive summary of biggest opportunities.

**Synthesis-Action Agent (4th, runs in parallel with the three lens agents above):**
> Read all review artifacts for {REVIEW_ID}:
> - The 9 original per-agent reviews:
>   - `{PACK_DIR}/standard-claude.md`, `{PACK_DIR}/standard-codex.md`, `{PACK_DIR}/standard-gemini.md`
>   - `{PACK_DIR}/critical-claude.md`, `{PACK_DIR}/critical-codex.md`, `{PACK_DIR}/critical-gemini.md`
>   - `{PACK_DIR}/evolutionary-claude.md`, `{PACK_DIR}/evolutionary-codex.md`, `{PACK_DIR}/evolutionary-gemini.md`
> - The full context document (the diff being reviewed):
>   - `notes/.tmp/trident-{REVIEW_ID}/team-review-context.md`
>
> **THIS IS A READ-ONLY REVIEW.** Your ONLY output is the synthesis file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.
>
> **Your job:** produce a validated, agent-consumable fix plan. A downstream agent will read your output and apply the fixes without re-reading the source reviews. Your output IS the action contract, so be precise.
>
> You do not have access to the three lens-synthesis docs (they are running in parallel with you). Do your own cross-reviewer dedup from the 9 originals. Cross-check claims against the diff in the context document.
>
> ## What "validated" means
>
> A finding is **validated** when one of:
> 1. **Multi-reviewer consensus**: 2+ of the 9 reviewers independently raised it. Strongest signal, especially when consensus spans lenses (e.g. Standard and Critical both flag it).
> 2. **Single-reviewer, cited, checkable**: one reviewer raised it but cited a specific file:line that, on inspection of the diff, obviously exhibits the claimed problem. Correctness bugs with concrete references self-validate.
>
> A finding is **not validated** (surface to user, do not put in the fix list) when:
> - Single-reviewer and subjective (style, taste, architectural preference).
> - Reviewers disagree on whether it's a problem, or on the correct fix.
> - The cited location doesn't match what the code actually does: reviewer misread.
> - The finding requires design discussion before the fix direction is clear.
>
> ## Output format
>
> Write to: `{PACK_DIR}/synthesis-action.md`.
>
> Use this exact structure:
>
> ```markdown
> # Action-Ready Synthesis: {REVIEW_ID}
>
> ## Verdict
> <one of: merge-ready | fix-then-merge | rework-then-review>
>
> ## Apply by default
>
> ### Blockers (merge-blocking)
> Numbered list. Each item:
> - **B<N>: <one-line issue title>**
>   - Location: `<file>:<line>` (or range)
>   - Problem: <concrete, 1 to 3 sentences>
>   - Fix: <concrete direction, 1 to 3 sentences>
>   - Sources: <which of the 9 reviewers flagged it; cite lens and model>
>
> ### Important (land in same PR)
> Same schema with **I<N>** prefix.
>
> ### Straightforward mediums
> Same schema with **M<N>** prefix. Only include mediums where the fix is well-scoped, in-place, does not touch code outside the diff's blast radius, and does not require design discussion.
>
> ### Evolutionary clear wins
> Same schema with **EW<N>** prefix. Only include evolutionary findings where the change is clearly beneficial, clearly low-risk, clearly in-scope for the current PR, and the kind of thing the user would plausibly have asked for. Err toward fewer. Most evolutionary content belongs in "Evolutionary worth considering" below or in `synthesis-evolutionary.md`.
>
> ## Surface to user (do not apply silently)
>
> Numbered list of items that are not validated-enough to apply by default. Each item:
> - **S<N>: <title>**
>   - Why deferred: <ambiguous | disagreement | design-needed | scope-creep | subjective>
>   - Summary: <what the reviewer(s) said and why the user should see it>
>   - Sources: <citations>
>
> ## Evolutionary worth considering (do not apply silently)
>
> Short, curated list, 0 to 3 items max. Evolutionary findings that are interesting and possibly valuable but expand scope, change direction, or represent a bet the user should weigh. Everything else from the evolutionary lens belongs in `synthesis-evolutionary.md` for the human to read directly.
>
> - **E<N>: <title>**
>   - Summary: <1 to 3 sentences>
>   - Why worth a look: <1 sentence>
>   - Sources: <citations>
> ```
>
> ## Rules of thumb
>
> - Err on the side of "surface to user" when in doubt. The cost of flagging an ambiguous item is minutes; the cost of silently applying a wrong fix is much higher.
> - Evolutionary clear wins are real and worth capturing, but they are rare. A typical review produces zero to one. If you find yourself populating this section with several items, you are probably being too permissive; move them to "Evolutionary worth considering" instead.
> - Every item in "Apply by default" should be something a competent agent could execute from your description alone, without re-reading the source reviews.
> - If the 9 reviews disagree on verdict (e.g. Critical says fail-impl, Standard says merge-ready), document the disagreement in the Verdict section and bias toward the more cautious verdict.
> - Preserve citations. Every item names its sources so the downstream agent (or human) can drill into the originals if needed.

---

Launch all four of these synthesis agents in a **single message** (4 Agent tool calls in one content block) so they execute in parallel.

### Phase 8: Launch for Review and Clean Up

Once all four synthesis docs are written:

```bash
open "{PACK_DIR}/synthesis-standard.md"
open "{PACK_DIR}/synthesis-critical.md"
open "{PACK_DIR}/synthesis-evolutionary.md"
open "{PACK_DIR}/synthesis-action.md"
```

**Clean up tmp staging directory** — only after confirming review pack files are present:
```bash
# Verify review pack is complete before cleanup
ACTUAL=$(ls {PACK_DIR}/*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$ACTUAL" -ge 9 ]; then
    rm -rf notes/.tmp/trident-{REVIEW_ID}
fi
```

(Use 9 as the threshold — if at least 9 reviews exist, the tmp files served their purpose.)

Tell the user:
> "Trident code review complete. Three synthesis docs opened:
> - `synthesis-standard.md` — analytical consensus and merge verdict
> - `synthesis-critical.md` — adversarial findings and production readiness
> - `synthesis-evolutionary.md` — creative opportunities and evolution paths
>
> Full review pack (12 files) at: `{PACK_DIR}/`"

### Phase 9: After Synthesis — default fix behavior (caller acts on findings)

Once the four syntheses are written and opened, the caller (you, the agent that ran `/trident-code-review`) is expected to act on the findings.

**`synthesis-action.md` is your action contract.** It already encodes the validation pass and the apply/surface split. Read it first; the three lens syntheses are reference material if you need narrative context for any specific item. You do not need to re-derive what to fix from the 9 raw reviews.

**Apply by default, no confirmation needed:**
- Every item under **Blockers** in `synthesis-action.md`.
- Every item under **Important**.
- Every item under **Straightforward mediums**.
- Every item under **Evolutionary clear wins** (these are validated-already by the action synthesizer; that section is intentionally short).

**Surface to user, do not apply silently:**
- Every item under **Surface to user** in `synthesis-action.md`.
- Every item under **Evolutionary worth considering**.

These two categories go in your post-review report for the user (or, if you're running inside a delegator pattern, into a Lattice comment for the delegator to weigh).

**How to apply fixes:**
- Group related fixes into logical commits with clear messages. One commit per finding is fine for small items; group when a single change addresses several related findings.
- Push after each commit (or small batch) so CI runs incrementally.
- If during application you discover that a finding is wrong (the cited location doesn't match the code, or the proposed fix breaks something), stop, do not apply blindly, and surface it to the user. The action synthesizer is fallible; trust your eyes on the actual code.

**Reporting back:**
After applying fixes, post a summary noting:
- Which blockers, importants, straightforward mediums, and evolutionary clear wins landed (with commit SHAs).
- Which items you surfaced to the user (from "Surface to user" and "Evolutionary worth considering"), with the action synthesizer's rationale plus your own annotation if you have one.
- Any findings you reclassified during application (e.g., something marked "apply by default" that turned out wrong, or vice versa).

If you're running as a Review sibling inside a delegator pattern, this summary goes on the Lattice ticket, not to the human directly. The delegator is the human's interface.

---

## Fallback

If an agent fails or isn't available, proceed with successful agents. Note failures in the relevant synthesis doc. If an entire model is unavailable (e.g., Codex is down), the synthesis still works with 2 inputs instead of 3.

---

Now begin. Prepare context, run tests, and orchestrate the nine-agent trident code review.
