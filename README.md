# Stage 11 — Educational Agentic Engineering Materials

Patterns from the working setup of a Stage 11 hyperengineer. Published as reference material for operators learning to build software with digital intelligences as first-class teammates.

This is what we actually run, every day. Not a sanitized demo. The files in this repo are pulled from a live operator's `~/.claude/` and the Stage 11 skills tree. Copy what fits. Replace what doesn't. The patterns transfer; the specifics will not.

────

## What's Here

| Artifact | What it is |
|---|---|
| [`commands/trident-code-review.md`](commands/trident-code-review.md) | Nine-reviewer multi-model code review. Claude + Codex + Gemini, three lenses each, four parallel synthesizers, one validated machine-actionable fix plan. |
| [`commands/trident-plan-review.md`](commands/trident-plan-review.md) | Same shape as trident code review, pointed at a plan or design document instead of a diff. |
| [`agents/`](agents/) | The lens prompt files the trident commands compose — `CodeReview-{Standard,Critical,Evolutionary}.md` and `PlanReview-{Standard,Adversarial,Evolutionary}.md`. Plain markdown, not slash commands; trident reads them from `~/.claude/agents/` by path. (For a single day-to-day review, use Claude Code's built-in `/code-review`.) |
| [`skills/lattice-orchestrator/`](skills/lattice-orchestrator/) | The build engine. Turns a finished spec + build plan into tickets, dispatches a fleet of delegator agents that produce one PR per ticket, and closes with a terminal audit run by an agent that read the spec cold. Overnight-capable. |
| [`skills/lattice-delegate/`](skills/lattice-delegate/) | The single-ticket sibling. One ticket, one dedicated pane, one isolated worktree, plan → implement → review → validate → PR. What the orchestrator dispatches N of; useful on its own when you have one ticket, not a run. |
| [`atins-global-claude-md-example.md`](atins-global-claude-md-example.md) | One operator's global `~/.claude/CLAUDE.md`. Loads into every Claude Code session on the machine. The headline pattern: language overloading. |
| [`commands/capture-skill.md`](commands/capture-skill.md) | Extract reusable knowledge from a conversation into a `CLAUDE.md` file or a new slash command. The flywheel for a self-improving codebase. |
| [`atins-statusline-example.sh`](atins-statusline-example.sh) | One operator's single adaptive Claude Code status line. Priority-ordered, collapses right-to-left as the pane narrows. Git worktree-aware, model colored by family, context + rate-limit gradients with a usage glide slope. |

────

## Trident Code Review

The flagship code review workflow. Significantly outperforms any off-the-shelf solution by an order of magnitude, due to the intense usage of nine different reviewers across three providers using three different code review prompts. Four parallel synthesizers consolidate the output into one machine-actionable fix plan, all from a single slash command.

```
trident-code-review
├── Phase 1-2: Build context (branch info, commits, full diff, test results)
├── Phase 3-4: Stage prompt files in notes/.tmp/
├── Phase 5: Launch nine reviewers in parallel
│     ├── Claude:  Standard, Critical, Evolutionary
│     ├── Codex:   Standard, Critical, Evolutionary
│     └── Gemini:  Standard, Critical, Evolutionary
├── Phase 6: Quality gate (drop empty or failed reviews)
├── Phase 7: Launch four synthesizers in parallel
│     ├── Standard lens consolidator
│     ├── Critical lens consolidator
│     ├── Evolutionary lens consolidator
│     └── Action-ready synthesizer (validated, machine-actionable fix plan)
└── Phase 8-9: Open the four syntheses, then apply default fixes
```

The fourth synthesizer is the load-bearing innovation. It reads all nine raw reviews plus the diff and produces a `synthesis-action.md` with two sections: **Apply by default** (validated findings the next agent commits without asking) and **Surface to user** (findings that need human judgment). Downstream agents read that one file as their action contract instead of re-deriving the fix list from nine documents.

That separation is what makes nine reviewers productive instead of overwhelming.

### Install

You will need [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (the orchestrator and the three Claude reviewers run here), [Codex CLI](https://github.com/openai/codex) (three Codex reviewers), and [Gemini CLI](https://github.com/google-gemini/gemini-cli) (three Gemini reviewers). If you skip Codex or Gemini, the workflow degrades gracefully to six or three reviewers and still produces a useful synthesis.

```bash
# Clone
git clone https://github.com/Stage-11-Agentics/educational-agentic-engineering-materials.git
cd educational-agentic-engineering-materials

# The slash command.
mkdir -p ~/.claude/commands
cp commands/trident-code-review.md ~/.claude/commands/

# Review-lens prompt files. Trident composes its Standard, Critical, and
# Evolutionary lenses from these three files in ~/.claude/agents/. They are
# not slash commands — trident reads them by path. (For day-to-day single
# reviews, use Claude Code's built-in /code-review.)
mkdir -p ~/.claude/agents
cp agents/CodeReview-Standard.md     ~/.claude/agents/
cp agents/CodeReview-Critical.md     ~/.claude/agents/
cp agents/CodeReview-Evolutionary.md ~/.claude/agents/

# Optional: hardlink the command into Codex CLI's prompt directory so the same
# file backs both `/trident-code-review` in Claude Code and the equivalent
# Codex prompt. Edit one, both update.
mkdir -p ~/.codex/prompts
ln ~/.claude/commands/trident-code-review.md ~/.codex/prompts/trident-code-review.md 2>/dev/null
```

### Run It

From any feature branch in any repo with diff against `dev`, `main`, or `master`:

```
/trident-code-review
```

Optional context goes after the command:

```
/trident-code-review pay particular attention to the new auth middleware
```

The orchestrator builds a context document with the diff, runs the project's test suite once, stages prompt files in `notes/.tmp/trident-<id>/`, spawns nine reviewers, gates on quality, runs four synthesizers in parallel, and opens all four syntheses. Total wall clock typically lands around five to ten minutes depending on diff size and the slowest reviewer.

The review pack lives at `notes/trident-review-<id>-pack-<timestamp>/`. Twelve files total: nine raw reviews, three lens syntheses, one action-ready synthesis. After the syntheses land, the orchestrator (you, the agent that ran the command) is expected to apply the default fixes and surface the rest.

────

## Trident Plan Review

Same shape as trident code review, pointed at a plan or design document instead of a diff. Same nine reviewers, same three lenses, same four synthesizers. Output is a validated revision plan instead of a fix plan.

```
/trident-plan-review path/to/PLAN.md
/trident-plan-review path/to/PLAN.md focus on assumptions about scale
```

Use it before implementation starts, when the cost of building the wrong thing is higher than the cost of one more review pass.

**Install** (in addition to the trident code review install above):

```bash
cp commands/trident-plan-review.md ~/.claude/commands/

# Three plan-review lens prompts the trident plan command spawns
cp agents/PlanReview-Standard.md      ~/.claude/agents/
cp agents/PlanReview-Adversarial.md   ~/.claude/agents/
cp agents/PlanReview-Evolutionary.md  ~/.claude/agents/

# Optional Codex hardlinks
ln ~/.claude/commands/trident-plan-review.md ~/.codex/prompts/trident-plan-review.md 2>/dev/null
```

────

## Lattice Orchestration

The build engine. Trident reviews the work; the orchestrator *does* the work — it takes a finished build contract and runs a fleet until there is one PR per ticket and an audit saying whether they add up to what was specified.

The contract arrives written (`SPEC.md` with numbered acceptance criteria, `EVALUATION.md` saying how each one gets verified and by whom, `BUILDPLAN.md` with the ticket breakdown). This skill does not plan and does not write that contract — deliberately, because it is going to be audited against it.

```
lattice-orchestrator
├── Phase 0: Intake & ticketing              [Orchestrator]
│     ├── Contract checks (validate, never author — flag gaps upstream)
│     ├── Pin install facts (status vocabulary, git remote name)
│     ├── Mint one Lattice ticket per build-plan item, dependencies linked
│     └── Write the validation plan — every criterion, one row, tagged
│           pre-merge-static (an agent can audit it) or post-merge-smoke (a human must)
├── Phase 1: Dispatch                        [Orchestrator → N delegators]
│     ├── One delegator per ticket, own pane, own git worktree
│     ├── Each walks plan → implement → review → validate → PR
│     ├── Press-ahead: spawn dependents at review, not at merge
│     └── Escalations re-surfaced every tick while they stand
└── Phase 2: Terminal validation             [Result Validator — fresh session]
      ├── Reads SPEC and the validation plan cold, no prior context
      ├── Walks every pre-merge-static row exactly as written
      └── Validation report + the operator's post-merge smoke checklist
```

**Separation of duties is the whole design.** Three context-isolated seats: the Orchestrator dispatches and *never implements*; the delegators build; the Result Validator audits against a spec its builders did not write, in a fresh session, because an agent grading its own homework grades generously. The validation plan is written before any code exists and is treated as a contract — the validator may not invent rows, substitute faster methods, or silently skip.

Four patterns here transfer even if you never install Lattice:

- **Verified state, not reported state.** Never act on what an agent *said* happened. The branch exists remotely or it doesn't (`git ls-remote`); the PR is non-empty or it isn't (`head.sha != base.sha`); the merge landed or it didn't (re-GET and assert `.merged == true`). A silently-failed push is the number one false-completion mode in autonomous runs.
- **A fired review is not a finished review.** Review gates fail *open*: the runner can die while its state file still says `running` forever, and a naive completion check passes on any review evidence in the ticket's lifetime — including a FAIL artifact from a previous rework cycle. Require evidence that postdates *this* cycle, names the reviewed commit, and carries a PASS.
- **Press-ahead.** Spawn dependent work when its dependency reaches *review*, not merge. Children branch off the in-review parent and inherit its interfaces import-stable. This is most of the wall-clock savings in a multi-wave run.
- **The footgun catalog.** When a new silent-failure mode appears mid-run, it goes in the run state *and* into every subsequent boot prompt — a catalog entry without a prompt update guarantees the next agent hits the same wall. Mitigated three times, or seen across two runs, and it graduates into the skill itself, with the war story kept in [`runs-ledger.md`](skills/lattice-orchestrator/runs-ledger.md) so the rule keeps its evidence.

The skill is four files: [`SKILL.md`](skills/lattice-orchestrator/SKILL.md) is the always-loaded spine; the three `references/` files are per-seat playbooks — [`intake.md`](skills/lattice-orchestrator/references/intake.md) (Phase 0 mechanics), [`orchestrator.md`](skills/lattice-orchestrator/references/orchestrator.md) (the dispatch loop, boot templates, worktree discipline, merge machinery, recovery, footguns), [`result-validator.md`](skills/lattice-orchestrator/references/result-validator.md) (the terminal audit protocol and report template). Each is loaded only by the agent sitting in that seat. That progressive-disclosure shape is itself worth stealing: a 90-line spine that always loads, and the operational depth pulled in only by whoever needs it.

### Requirements, and what degrades

Two Stage 11 tools, both open source: [**Lattice**](https://github.com/Stage-11-Agentics/lattice) (the ticket board and the review/validation CLI — this skill is named for its substrate, and a different substrate would be a different skill) and [**c11**](https://github.com/Stage-11-Agentics/c11) (the terminal multiplexer that gives every delegator a visible pane you can scrub). Outside c11 the run still works — the delegators need any harness that can spawn parallel sub-sessions — but the workspace geometry, the live board surface, and the pane-scrubbing all degrade to whatever your harness offers.

The upstream stages that *author* the contract (Stage 11's Tone workflow — initiation, prototype, architecture) are not published here; `SKILL.md` references them because that is how it actually runs. Nothing stops you: hand it a `SPEC.md`, an `EVALUATION.md`, and a `BUILDPLAN.md` from any source, including your own hand, and it runs standalone. If those artifacts don't exist yet, the skill's correct behavior is to refuse and say so.

### Install

```bash
cp -r skills/lattice-orchestrator ~/.claude/skills/
cp -r skills/lattice-delegate     ~/.claude/skills/   # the single-ticket sibling
```

### Run It

From a repo with a build contract in it:

```
orchestrate this
```

Phase 0 is a short config dialogue — autonomy level, how many delegators run concurrently, whether PRs auto-merge or stop at review — with defaults auto-suggested from the size of the plan. Then it tells you exactly what Phase 1 will look like (how many panes appear, how escalations reach you, what "done" means) before it spawns anything. Set autonomy to Fully Autonomous and it will run a plan overnight and have a validation report waiting.

────

## The CLAUDE.md File: Atin's Global Example

[`atins-global-claude-md-example.md`](atins-global-claude-md-example.md) is Atin's publishable pattern that influences all of his agentic coding. It may provide some interesting examples and useful tools for you.

A global `CLAUDE.md` lives at `~/.claude/CLAUDE.md` and loads into every Claude Code session, before the operator types a word. It is the contract between the operator and the agents they work with: vocabulary, defaults, escalation rules, the patterns the operator wants the agents to apply by reflex.

The headline pattern is **language overloading**. Single-word triggers that invoke specific agent behaviors. Defined once, used everywhere.

| Trigger | Behavior |
|---|---|
| `clear` | Spawn a fresh, headless agent with isolated context |
| `new instance` | Launch a Claude Code session in a new c11 pane |
| `loopy` | Drive a full validation loop. Implement, validate, iterate until actually done. |
| `dialogue` | Pause and ask every question needed before building |

These are the most under-discussed leverage points in agentic engineering. Defined once in a global file, they collapse the cost of explaining what you want from a paragraph to a word. The agent enters a different mode. Misunderstanding drops. Throughput rises.

The full file goes deeper: clear-agent launching, loopy validation, dialogue-driven development, parallelization defaults, the c11 workspace assumption, the auto-commit and auto-push policy, environment confirmation, AskUserQuestion best practices, thrashing detection, and a self-improvement habit for keeping `CLAUDE.md` current.

Treat it as a reference implementation. Steal the table. Steal the structure. Build your own vocabulary on top.

**Install:**

```bash
# Back up your existing global CLAUDE.md if you have one
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak 2>/dev/null

# Copy this one in (or merge it with yours)
cp atins-global-claude-md-example.md ~/.claude/CLAUDE.md
```

────

## Capture-Skill

After a conversation that uncovered a useful workflow, a non-obvious gotcha, or a pattern worth keeping, run:

```
/capture-skill
```

The agent extracts what it learned and writes it into either the project's `CLAUDE.md` or a new slash command. The next session starts with what this one figured out. Used regularly, it compounds. The codebase becomes a memory the team writes to and reads from.

**Install:**

```bash
cp commands/capture-skill.md ~/.claude/commands/
```

────

## Status Line

A single status line from the operator's live `~/.claude/`. Claude Code runs the script on every message and renders whatever it prints, so this is a persistent, at-a-glance readout of the session and the working tree. Every group is **always shown in full, regardless of pane width** — the only width-dependent formatting is the working directory shrinking to a basename below ~150 cols:

```
# wide pane
18%  [opus-4.8·1M high]  184k/$1.23  5h(3.5h): 53%(◇30%) 7d(5.0d): 39%(◇29%)   ⎇ main ●44  ~/Projects/Gregorovich/projects/acetate   +156 -23  2:23 api_time

# narrow pane (<150 cols) — same groups, path shrinks to a basename
18%  [opus-4.8·1M high]  184k/$1.23  5h(3.5h): 53%(◇30%) 7d(5.0d): 39%(◇29%)   ⎇ main ●44  acetate   +156 -23  2:23 api_time
```

Five groups, left to right:

- **Core** — context-window usage with a green→yellow→red gradient, then the model name and reasoning effort inside the brackets. Model colored by family (opus white, sonnet blue, haiku pink, fable purple); effort styled by intensity (italic below high, bold above, and never alarm-red).
- **Tokens/cost** — token count in flat white (the higher-priority read), `$cost` dimmed alongside it. Sits immediately right of the model bracket.
- **Budget** — the 5-hour and 7-day rate-limit windows, each rendered `window(time-left): used%(◇pace%)`. The `◇` is a **glide slope**: where you'd be if usage were spread evenly across the window. Under it is headroom; over it means you're burning faster than even. Dim until `used%` crosses the per-window threshold (yellow, red at 95%), so it stays quiet until it matters. Renders `5h:(no data)` / `7d:(no data)` per window when the account has no rate-limit info, instead of dropping silently.
- **Location** — git worktree name, branch with a dirty-file count, and working directory (full path when wide, basename when tight) — the worktree field is what tells parallel agents apart, the thing most off-the-shelf status lines miss.
- **Stats** — lines added/removed, open PR number + review state, and API time (`api_time`).

Almost everything is read straight from the JSON Claude Code pipes to the script: `workspace.git_worktree`, `context_window.used_percentage`, `effort.level`, `rate_limits.*` (including `resets_at`, for the time-left and glide-slope math), `pr.*`. The only shell-out is the git branch and dirty count, cached per `session_id` on a three-second TTL so it stays fast even though it fires after every message. Absent fields — no worktree, no open PR, no rate limits on a non-subscription account — simply drop out, so the line degrades cleanly anywhere.

**Install:**

```bash
# Requires jq and a truecolor + unicode-capable terminal (Ghostty, iTerm2, WezTerm, Kitty).
brew install jq   # or: apt-get install jq

cp atins-statusline-example.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then point your settings at it in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

────

## Adapt, Don't Copy Wholesale

The patterns transfer. The specifics often don't.

The global `CLAUDE.md` was shaped by one operator's actual work. Some triggers will land in your context. Others won't. The trident review prompts assume a particular review aesthetic, terse, lens-aware, action-synthesizing. Your team might want a different cut. The underlying patterns transfer; the implementation will look different.

Read the files. Understand the shape. Build your own.

────

## About Stage 11

[Stage 11](https://stage11.ai) builds digital intelligences and the infrastructure they need to operate as first-class engineering peers. The work in this repository is part of how we build, every day. We publish it because the patterns are too useful to keep private and because the next generation of operators is going to need them.

The Stage 11 projects most relevant to this repo:

- [**c11**](https://github.com/Stage-11-Agentics/c11). Native macOS terminal multiplexer.
- [**Lattice**](https://github.com/Stage-11-Agentics/lattice). File-based agent-native task tracker.

────

## License

MIT. Use these patterns however they serve you.
