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

A single adaptive status line from the operator's live `~/.claude/`. Claude Code runs the script on every message and renders whatever it prints, so this is a persistent, at-a-glance readout of the session and the working tree. It is **priority-ordered left-to-right and collapses right-to-left as the pane narrows** — Claude passes the pane width in `$COLUMNS`, and the script sheds whole groups to fit:

```
# wide pane (≈150+ cols) — everything
18%  [opus-4.8·1M high]  184k/$1.23   5h(3.5h): 53%(◇30%) 7d(5.0d): 39%(◇29%)   ⎇ main ●44  ~/Projects/Gregorovich/projects/acetate   +156 -23  2:23 api_time

# ~110 cols — stats dropped, path shrinks to a basename
18%  [opus-4.8·1M high]  184k/$1.23   5h(3.5h): 53%(◇30%) 7d(5.0d): 39%(◇29%)   ⎇ main ●44  acetate

# ~80 cols — only the core and the token/cost readout survive
18%  [opus-4.8·1M high]  184k/$1.23

# narrow split — context and model never drop
18%  [opus-4.8·1M high]
```

Five groups, in priority order:

- **Core** (never dropped) — context-window usage with a green→yellow→red gradient, then the model name and reasoning effort inside the brackets. Model colored by family (opus white, sonnet blue, haiku pink, fable purple); effort styled by intensity (italic below high, bold above, and never alarm-red).
- **Tokens/cost** — token count in flat white (the higher-priority read), `$cost` dimmed alongside it. Sits immediately right of the model bracket.
- **Budget** — the 5-hour and 7-day rate-limit windows, each rendered `window(time-left): used%(◇pace%)`. The `◇` is a **glide slope**: where you'd be if usage were spread evenly across the window. Under it is headroom; over it means you're burning faster than even. Dim until `used%` crosses the per-window threshold (yellow, red at 95%), so it stays quiet until it matters.
- **Location** — git worktree name, branch with a dirty-file count, and working directory (full path when wide, basename when tight) — the worktree field is what tells parallel agents apart, the thing most off-the-shelf status lines miss.
- **Stats** — lines added/removed, open PR number + review state, and API time (`api_time`). First to go when space is tight.

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
