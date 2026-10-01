# Trident Plan Review: Nine-Agent Plan Review

Run parallel plan reviews using Claude, Codex, and Gemini — each provider runs three lenses: Standard (analytical), Adversarial (critical), and Evolutionary (exploratory). Output lives alongside the input file in a review pack folder.

**Usage:**
- `/user:trident-plan-review <file>` — Review a plan/document through all nine agents
- `/user:trident-plan-review <file> <additional notes>` — Review with additional context
- `$ARGUMENTS` contains the file path and optional additional notes

**How to invoke:** a single agent runs this command. The nine reviewers and four synthesizers are that agent's sub-agents and headless bash sessions. They do NOT need their own areas or tabs. If you're a Plan-review sibling inside a delegator pattern, you invoke `/trident-plan-review` from your one tab and the 9+4 run under you.

---

## Critical Rule: READ-ONLY applies to the 9 reviewers and 4 synthesizers

The **nine review agents and four synthesis agents** are strictly read-only. They must ONLY:
- Read existing files (the plan, prompt files, related context)
- Write their single designated output file to the review pack folder

They must NEVER:
- Commit or push to git
- Modify any existing files (including the plan being reviewed)
- Create files outside the review pack folder or the tmp staging directory
- Run destructive commands of any kind

Enforce this in every launch message. Agents that try to commit, modify source files, or take actions beyond writing their review output are violating the contract.

**The caller (the agent that invoked `/trident-plan-review`) is NOT read-only.** After the syntheses land, the caller is expected to act on the findings. See "After Synthesis" below.

---

## Architecture

```
Main Agent (Opus 4.6)
├── Parse file + notes from $ARGUMENTS
├── Create review pack folder alongside input file
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
│   ├── Adversarial lens (reads 3 adversarial reviews)
│   ├── Evolutionary lens (reads 3 evolutionary reviews)
│   └── Action-ready (reads all 9 originals + plan input; agent-consumable revision plan)
├── Open all 4 synthesis docs
└── Clean up tmp staging directory
```

After all 9 complete, launch 4 synthesis agents in a single parallel batch. Three lens synthesizers each consolidate one lens across the three models; a fourth action-ready synthesizer reads all 9 originals plus the input plan and produces a validated, machine-actionable revision plan. All four run in parallel so total runtime is bounded by the slowest single synthesis, not the sum.

---

## Instructions

### Phase 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **First argument:** file path (required)
- **Everything after:** additional user notes (optional)

Read the input file. If it doesn't exist or is empty, stop and tell the user.

Derive `REVIEW_ID` from **both the parent directory and filename** (strip path prefix, lowercase, hyphens for spaces):
- `projects/music_fetcher/PLAN.md` -> `music-fetcher-plan`
- `notes/api-redesign-plan.md` -> `api-redesign-plan`
- `plans/Q3 Roadmap.md` -> `q3-roadmap`

This prevents collisions when reviewing identically-named files in different directories.

Determine the directory where the input file lives (`INPUT_DIR`).

### Phase 1b: Identify Related Context

Look for files that would help reviewers ground their feedback:
- Sibling files in the same directory (e.g., `CLAUDE.md`, other docs)
- Related projects with similar patterns (e.g., `movie_fetcher` when reviewing `music_fetcher`)
- Any files referenced in the plan itself

Build a `CONTEXT_NOTE` string listing these paths, e.g.:
> "For additional context, you may also read these related files: `projects/music_fetcher/CLAUDE.md`, `projects/movie_fetcher/PLAN.md` (sibling project with same pattern)."

If no relevant context is found, set `CONTEXT_NOTE` to empty.

### Phase 2: Create Review Pack

Generate a timestamp:
```bash
date +%Y-%m-%dT%H%M
```

Create the review pack folder alongside the input file:
```bash
mkdir -p "{INPUT_DIR}/{REVIEW_ID}-review-pack-{TIMESTAMP}"
```

Example: If reviewing `projects/music_fetcher/PLAN.md`, the pack goes at `projects/music_fetcher/music-fetcher-plan-review-pack-2026-03-10T1423/`.

Store this path as `PACK_DIR`.

### Phase 3: Prepare Prompt Files

Create a tmp staging directory:
```bash
mkdir -p notes/.tmp/trident-{REVIEW_ID}
```

**For Codex and Gemini**, use the file-reference approach to avoid shell escaping issues. Write each agent's full prompt to a tmp file rather than passing it inline.

For each of the 6 Codex/Gemini agents, write a prompt file:
```bash
# Example for one agent — repeat for all 6
cat > notes/.tmp/trident-{REVIEW_ID}/prompt-standard-codex.md <<'EOF'
Read ~/.codex/agents/PlanReview-Standard.md for your review approach and thinking framework. Then read {INPUT_FILE} — that is the document you are reviewing.

**THIS IS A READ-ONLY REVIEW.** Your ONLY output is the review file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.

**OUTPUT:** Write your review to `{PACK_DIR}/standard-codex.md`

Use these values: PLAN_ID={REVIEW_ID}, MODEL=Codex.
{CONTEXT_NOTE}
{ADDITIONAL_NOTES}

Now follow the instructions in the prompt file.
EOF
```

For Gemini, also copy the prompt framework files into the workspace (Gemini sandboxes reads to the workspace):
```bash
cp ~/.claude/agents/PlanReview-Standard.md notes/.tmp/trident-{REVIEW_ID}/
cp ~/.claude/agents/PlanReview-Adversarial.md notes/.tmp/trident-{REVIEW_ID}/
cp ~/.claude/agents/PlanReview-Evolutionary.md notes/.tmp/trident-{REVIEW_ID}/
```

If the input file is outside the workspace, also copy it:
```bash
cp {INPUT_FILE} notes/.tmp/trident-{REVIEW_ID}/plan-input.md
```

For Gemini prompt files, use workspace-local paths for both the framework file and the input file.

### Phase 4: Launch All Nine Agents

**Launch message template** (for Claude subagents — Codex/Gemini use their prompt files from Phase 3):
> Read {PROMPT_PATH} for your review approach and thinking framework. Then read {INPUT_FILE} — that is the document you are reviewing.
>
> **THIS IS A READ-ONLY REVIEW.** Your ONLY output is the review file specified below. Do NOT commit, push, modify existing files, or take any action beyond writing this single file.
>
> **OUTPUT:** Write your review to `{PACK_DIR}/{lens}-{model}.md` — NOT to the path mentioned in the prompt file.
>
> Use these values: PLAN_ID={REVIEW_ID}, MODEL={MODEL}.
> {CONTEXT_NOTE}
> Additional context from the user: {ADDITIONAL_NOTES}
>
> Now follow the instructions in the prompt file.

---

**Claude agents** (3x) — use the **Agent tool** (parallel subagents):

Launch three Agent tool calls in a single message with the launch template, substituting:
- Standard: `PROMPT_PATH=~/.claude/agents/PlanReview-Standard.md`, `lens=standard`, `MODEL=Claude`
- Adversarial: `PROMPT_PATH=~/.claude/agents/PlanReview-Adversarial.md`, `lens=adversarial`, `MODEL=Claude`
- Evolutionary: `PROMPT_PATH=~/.claude/agents/PlanReview-Evolutionary.md`, `lens=evolutionary`, `MODEL=Claude`

---

**Codex agents** (3x) — use Bash with `run_in_background: true`:

**Important:** Use `env -u CLAUDECODE` to strip the environment variable that blocks nested sessions.

Each agent reads its prompt from the file written in Phase 3:

```bash
env -u CLAUDECODE codex exec --full-auto --skip-git-repo-check "Read notes/.tmp/trident-{REVIEW_ID}/prompt-standard-codex.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/codex-standard.log

env -u CLAUDECODE codex exec --full-auto --skip-git-repo-check "Read notes/.tmp/trident-{REVIEW_ID}/prompt-adversarial-codex.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/codex-adversarial.log

env -u CLAUDECODE codex exec --full-auto --skip-git-repo-check "Read notes/.tmp/trident-{REVIEW_ID}/prompt-evolutionary-codex.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/codex-evolutionary.log
```

---

**Gemini agents** (3x) — use Bash with `run_in_background: true`:

Each agent reads its prompt from the file written in Phase 3:

```bash
gemini -m gemini-3-pro-preview --yolo "Read notes/.tmp/trident-{REVIEW_ID}/prompt-standard-gemini.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/gemini-standard.log

gemini -m gemini-3-pro-preview --yolo "Read notes/.tmp/trident-{REVIEW_ID}/prompt-adversarial-gemini.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/gemini-adversarial.log

gemini -m gemini-3-pro-preview --yolo "Read notes/.tmp/trident-{REVIEW_ID}/prompt-evolutionary-gemini.md and follow the instructions exactly." 2>&1 | tee notes/.tmp/trident-{REVIEW_ID}/gemini-evolutionary.log
```

---

**Tell the user:**
> "Plan: {input_file} | Review Pack: {PACK_DIR}
>
> Launched 9 agents (3 Standard, 3 Adversarial, 3 Evolutionary) across Claude, Codex, and Gemini.
>
> You can continue working. I'll synthesize when complete."

### Phase 5: Wait, Collect, and Quality Gate

- For Claude agents: the Agent tool calls will return when complete.
- For Codex/Gemini agents: use `TaskOutput` with `block: true` for each background Bash task.

**Quality gate:** Verify output files exist and have substance:
```bash
wc -c {PACK_DIR}/*.md
```

- Files over 500 bytes: good, proceed to synthesis.
- Files under 500 bytes: likely failed or empty. Check the corresponding log in `notes/.tmp/trident-{REVIEW_ID}/` and note the gap.
- Missing files: check logs, note which agent failed.

Report any gaps to the user before proceeding to synthesis.

Expected files: `standard-claude.md`, `standard-codex.md`, `standard-gemini.md`, `adversarial-claude.md`, `adversarial-codex.md`, `adversarial-gemini.md`, `evolutionary-claude.md`, `evolutionary-codex.md`, `evolutionary-gemini.md`.

### Phase 6: Four Synthesis Agents (parallel)

Launch **four Agent tool calls in a single message** so they run in parallel. Three synthesize one lens each across the three models; the fourth produces the action-ready validated revision plan directly from the 9 originals plus the input plan being reviewed.

Total wall-clock runtime for this phase is bounded by the slowest single synthesis, not the sum.

**Synthesis-Standard Agent:**
> Read the following three reviews and synthesize them into a single cohesive document:
> - `{PACK_DIR}/standard-claude.md`
> - `{PACK_DIR}/standard-codex.md`
> - `{PACK_DIR}/standard-gemini.md`
>
> These are Standard/Analytical reviews of the same plan from three different AI models. Your job:
> 1. Where do models agree? (highest confidence findings)
> 2. Where do they diverge? (the disagreement itself is signal)
> 3. What unique insights did only one model surface?
> 4. Consolidated questions for the plan author (deduplicated, numbered)
> 5. Overall readiness verdict synthesized across all three
>
> Write your synthesis to: `{PACK_DIR}/synthesis-standard.md`
> Format as a clean, numbered-list-heavy document. Start with an executive summary.

**Synthesis-Adversarial Agent:**
> Read the following three reviews and synthesize them into a single cohesive document:
> - `{PACK_DIR}/adversarial-claude.md`
> - `{PACK_DIR}/adversarial-codex.md`
> - `{PACK_DIR}/adversarial-gemini.md`
>
> These are Adversarial/Critical reviews of the same plan from three different AI models. Your job:
> 1. Consensus risks — what do multiple models flag? (highest priority)
> 2. Unique concerns — risks only one model raised (worth investigating)
> 3. Assumption audit — merge and deduplicate all surfaced assumptions
> 4. The uncomfortable truths — what hard messages recur across models?
> 5. Consolidated hard questions for the plan author (deduplicated, numbered)
>
> Write your synthesis to: `{PACK_DIR}/synthesis-adversarial.md`
> Format as a clean, numbered-list-heavy document. Start with an executive summary.

**Synthesis-Evolutionary Agent:**
> Read the following three reviews and synthesize them into a single cohesive document:
> - `{PACK_DIR}/evolutionary-claude.md`
> - `{PACK_DIR}/evolutionary-codex.md`
> - `{PACK_DIR}/evolutionary-gemini.md`
>
> These are Evolutionary/Exploratory reviews of the same plan from three different AI models. Your job:
> 1. Consensus direction — evolution paths multiple models identified
> 2. Best concrete suggestions — the most actionable ideas across all three
> 3. Wildest mutations — the most creative/ambitious ideas (even if risky)
> 4. Flywheel opportunities — self-reinforcing loops any model identified
> 5. Strategic questions for the plan author (deduplicated, numbered)
>
> Write your synthesis to: `{PACK_DIR}/synthesis-evolutionary.md`
> Format as a clean, numbered-list-heavy document. Start with an executive summary.

**Synthesis-Action Agent (4th, runs in parallel with the three lens agents above):**
> Read all review artifacts for {REVIEW_ID}:
> - The 9 original per-agent reviews:
>   - `{PACK_DIR}/standard-claude.md`, `{PACK_DIR}/standard-codex.md`, `{PACK_DIR}/standard-gemini.md`
>   - `{PACK_DIR}/adversarial-claude.md`, `{PACK_DIR}/adversarial-codex.md`, `{PACK_DIR}/adversarial-gemini.md`
>   - `{PACK_DIR}/evolutionary-claude.md`, `{PACK_DIR}/evolutionary-codex.md`, `{PACK_DIR}/evolutionary-gemini.md`
> - The plan being reviewed:
>   - `{INPUT_FILE}` (or `notes/.tmp/trident-{REVIEW_ID}/plan-input.md` if a workspace-local copy was made)
>
> **THIS IS A READ-ONLY REVIEW.** Your ONLY output is the synthesis file specified below. Do NOT commit, push, modify existing files (including the plan), or take any action beyond writing this single file.
>
> **Your job:** produce a validated, agent-consumable revision plan. A downstream agent (or human) will read your output and apply the revisions to the plan without re-reading the source reviews. Your output IS the action contract, so be precise.
>
> You do not have access to the three lens-synthesis docs (they are running in parallel with you). Do your own cross-reviewer dedup from the 9 originals. Cross-check claims against what the plan actually says.
>
> ## What "validated" means
>
> A finding is **validated** when one of:
> 1. **Multi-reviewer consensus**: 2+ of the 9 reviewers independently raised it. Strongest signal, especially when consensus spans lenses.
> 2. **Single-reviewer, cited, checkable**: one reviewer raised it but cited a specific section/quote in the plan that, on inspection, obviously exhibits the claimed problem. Concrete textual issues self-validate.
>
> A finding is **not validated** (surface to user, do not put in the revision list) when:
> - Single-reviewer and subjective (style, taste, preferred framing).
> - Reviewers disagree on whether it's a problem, or on the correct revision.
> - The cited section doesn't match what the plan actually says: reviewer misread.
> - The finding requires the plan author's intent or the operator's strategic call before the revision direction is clear.
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
> <one of: plan-ready | revise-then-proceed | rework-then-rereview>
>
> ## Apply by default
>
> ### Blockers (plan is not yet executable as written)
> Numbered list. Each item:
> - **B<N>: <one-line issue title>**
>   - Where in the plan: <section, heading, or short quote>
>   - Problem: <concrete, 1 to 3 sentences>
>   - Revision: <concrete edit direction, 1 to 3 sentences>
>   - Sources: <which of the 9 reviewers flagged it; cite lens and model>
>
> ### Important (revise before implementation starts)
> Same schema with **I<N>** prefix.
>
> ### Straightforward mediums
> Same schema with **M<N>** prefix. Only include mediums where the revision is well-scoped, in-place, and does not require design discussion (e.g. add a missing edge case, clarify ambiguous wording, fill a known gap).
>
> ### Evolutionary clear wins
> Same schema with **EW<N>** prefix. Only include evolutionary findings where the change to the plan is clearly beneficial, clearly low-risk, clearly in-scope for the current revision pass, and the kind of thing the plan author would plausibly have asked for. Err toward fewer. Most evolutionary content belongs in "Evolutionary worth considering" below or in `synthesis-evolutionary.md`.
>
> ## Surface to user (do not apply silently)
>
> Numbered list of items that are not validated-enough to apply by default. Each item:
> - **S<N>: <title>**
>   - Why deferred: <ambiguous | disagreement | design-needed | scope-creep | subjective | author-intent-needed>
>   - Summary: <what the reviewer(s) said and why the plan author or operator should see it>
>   - Sources: <citations>
>
> ## Evolutionary worth considering (do not apply silently)
>
> Short, curated list, 0 to 3 items max. Evolutionary findings that are interesting and possibly valuable but expand scope, change the plan's direction, or represent a bet the plan author should weigh. Everything else from the evolutionary lens belongs in `synthesis-evolutionary.md` for the human to read directly.
>
> - **E<N>: <title>**
>   - Summary: <1 to 3 sentences>
>   - Why worth a look: <1 sentence>
>   - Sources: <citations>
> ```
>
> ## Rules of thumb
>
> - Err on the side of "surface to user" when in doubt. The cost of flagging an ambiguous item is minutes; the cost of silently rewriting a plan in a wrong direction is much higher.
> - Plans are higher-stakes to silently edit than code. Strategic intent lives in plans; bias more conservatively toward "surface to user" than the code-review version of this synthesizer would.
> - Evolutionary clear wins for plans are real but rare. A typical plan review produces zero to one. If you find yourself populating this section with several items, you are probably being too permissive.
> - Every item in "Apply by default" should be a revision a competent agent could execute from your description alone, without re-reading the source reviews.
> - If the 9 reviews disagree on verdict (e.g. Adversarial says rework, Standard says plan-ready), document the disagreement in the Verdict section and bias toward the more cautious verdict.
> - Preserve citations. Every item names its sources so the downstream agent (or human) can drill into the originals.

---

Launch all four of these synthesis agents in a **single message** (4 Agent tool calls in one content block) so they execute in parallel.

### Phase 7: Launch for Review and Clean Up

Once all four synthesis docs are written:

```bash
open "{PACK_DIR}/synthesis-standard.md"
open "{PACK_DIR}/synthesis-adversarial.md"
open "{PACK_DIR}/synthesis-evolutionary.md"
open "{PACK_DIR}/synthesis-action.md"
```

**Clean up tmp staging directory** — only after confirming all review pack files are present:
```bash
# Verify review pack is complete before cleanup
ACTUAL=$(ls {PACK_DIR}/*.md | wc -l | tr -d ' ')
if [ "$ACTUAL" -ge 9 ]; then
    rm -rf notes/.tmp/trident-{REVIEW_ID}
fi
```

(Use 9 as the threshold: syntheses are the proof that reviews were consumed. If at least 9 reviews exist, the tmp files served their purpose.)

Tell the user:
> "Trident plan review complete. Four synthesis docs opened:
> - `synthesis-standard.md` — analytical consensus
> - `synthesis-adversarial.md` — critical findings
> - `synthesis-evolutionary.md` — evolutionary opportunities
> - `synthesis-action.md` — agent-consumable revision plan
>
> Full review pack (13 files) at: `{PACK_DIR}/`"

### Phase 8: After Synthesis — default revision behavior (caller acts on findings)

Once the four syntheses are written and opened, the caller (you, the agent that ran `/trident-plan-review`) is expected to act on the findings.

**`synthesis-action.md` is your action contract.** It already encodes the validation pass and the apply/surface split. Read it first; the three lens syntheses are reference material if you need narrative context for any specific item. You do not need to re-derive what to revise from the 9 raw reviews.

**Apply by default to the plan, no confirmation needed:**
- Every item under **Blockers** in `synthesis-action.md`.
- Every item under **Important**.
- Every item under **Straightforward mediums**.
- Every item under **Evolutionary clear wins**.

**Surface to user, do not apply silently:**
- Every item under **Surface to user**.
- Every item under **Evolutionary worth considering**.

These two categories go in your post-review report for the user (or, if you're running inside a delegator pattern, into a Lattice comment for the delegator to weigh).

**How to apply revisions:**
- Edit the plan file directly. Group related revisions into a single coherent edit pass; don't write 14 individual diffs to the plan when one structured rewrite of an affected section will do.
- If the plan is checked into git, commit the revisions with a clear message that references the review pack. One commit (or a small handful) is appropriate.
- If during application you discover that a finding is wrong (the cited section doesn't match the plan, or the proposed revision contradicts the plan's stated intent elsewhere), stop, do not apply blindly, and surface it to the user. The action synthesizer is fallible; trust your eyes on the actual plan.

**Reporting back:**
After applying revisions, post a summary noting:
- Which blockers, importants, straightforward mediums, and evolutionary clear wins were absorbed into the plan.
- Which items you surfaced to the user (from "Surface to user" and "Evolutionary worth considering"), with rationale.
- Any findings you reclassified during application.

If you're running as a Plan-review sibling inside a delegator pattern, this summary goes on the Lattice ticket, not to the human directly. The delegator is the human's interface.

---

## Fallback

If an agent fails or isn't available, proceed with successful agents. Note failures in the relevant synthesis doc. If an entire model is unavailable (e.g., Codex is down), the synthesis still works with 2 inputs instead of 3.

---

Now begin. Parse the file from $ARGUMENTS and orchestrate the nine-agent trident plan review.
