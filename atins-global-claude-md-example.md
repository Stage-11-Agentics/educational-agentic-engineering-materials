# Atin's Global CLAUDE.md — Example

This is the global `~/.claude/CLAUDE.md` used by Atin Woodard, a Stage 11 hyperengineer. It loads into every Claude Code session on the machine and shapes how the agent interprets requests. We publish it as an example: study the patterns, copy what fits, replace what doesn't.

The headline pattern is **language overloading**: single-word triggers that invoke specific agent behaviors. The terminal-multiplexer specifics assume [c11](https://github.com/Stage-11-Agentics/c11), an open-source Stage 11 project. If you don't use it, ignore those sections.

This file is intentionally lean. Details live in skills (`/skill-name`), reference files, or component-specific `CLAUDE.md` layers. Only essential triggers and patterns belong at the global level.

────

## Language Overloading

These terms have overloaded meanings. When you see them, they trigger specific behavior:

| Term | Meaning |
|------|---------|
| **clear** | Spawn a fresh, headless agent with isolated context |
| **new instance** / **cmux instance** | Launch a Claude Code session in a new c11 area |
| **loopy** | Attempt the full loop: implement, validate, iterate, report |
| **dialogue** | Enter dialogue-driven development mode: ask every question needed before building |

See sections below for details.

## Launching Clear Agents (Headless Background)

**Trigger:** "clear", "launch a clear claude/codex/gemini"

Headless, non-interactive, runs via the Bash tool. The agent executes and returns results, no human in the loop.

| Trigger | Command |
| --- | --- |
| "Launch a clear claude" | `env -u CLAUDECODE claude -p "prompt" --dangerously-skip-permissions` |
| "Launch a clear codex" | `codex exec --full-auto --skip-git-repo-check "prompt"` |
| "Launch a clear gemini" | `gemini -m gemini-3-pro-preview --yolo "prompt"` |

`env -u CLAUDECODE` strips the env var that blocks nested Claude sessions when the Bash tool runs Claude as a subprocess.

**For code that spawns `claude` subprocesses:** strip `CLAUDECODE` from the subprocess environment programmatically. In Python: `env = os.environ.copy(); env.pop("CLAUDECODE", None)` and pass `env=env` to `subprocess.run()` / `Popen()`.

Run with `run_in_background: true` and monitor via `TaskOutput`.

**Tip:** "clear codex" or "clear gemini" is useful for getting cross-model perspectives on a review or analysis.

**Sub-agent permissions:** any Claude subprocess that runs without a human watching must use `--dangerously-skip-permissions`. Without it, the sub-agent stalls on every tool call waiting for permission approval that nobody will grant.

## 'Loopy' Tasks (End-to-End Autonomy)

**"Loopy"** means: attempt the current task as close to a full loop yourself. Implement, validate, iterate, report. A loopy task doesn't stop at "I've made the changes," it validates as best as possible. Not every task should be loopy: don't steamroll situations that genuinely need human involvement.

In practice, loopy means using tools like curl, the iOS Simulator MCP, or browser automation to validate the work. It means unblocking and unleashing the agent.

**Validation tools worth knowing:**
- **iOS Simulator MCP** (`mcp__ios-simulator-mcp__*`): screenshots, tap flows, verify UI. Effective for iOS validation.
- **Mobile MCP** (`mcp__mobile-mcp__*`): Android emulator automation. Use for Android validation, not iOS.
- **c11 embedded browser** (`c11 browser *` / `open <url>`): preferred for web validation when running inside c11. Faster and lighter than Chrome MCP.
- **Claude-in-Chrome** (`mcp__claude-in-chrome__*`): full Chrome automation. Use only outside c11 or when Chrome-specific features are needed.

**Stay in the loop.** If a fix doesn't work, try another approach. If tests fail, investigate. Iterate until the task is complete or you hit a real blocker requiring human input.

## 'Dialogue-Driven Development'

**"Dialogue"** means: pause execution and enter a collaborative conversation to fully understand requirements before building. The model is empowered to ask as many questions as necessary. Ignore normal "be concise / move fast" defaults.

**Why this matters:** Models have broad knowledge of patterns, tradeoffs, and pitfalls. That intelligence is wasted if the model charges ahead with assumptions instead of surfacing what it knows. Dialogue-driven development creates space for the model's knowledge to combine with the operator's context. The result is a shared understanding that produces more accurate, well-considered solutions than either could reach alone.

**Core principle:** Use `AskUserQuestion` liberally. Ask every question needed to eliminate ambiguity. 5 questions, 10, 20 are all acceptable. Do not proceed with assumptions when you could ask.

**When to enter dialogue mode:**
- Operator explicitly invokes it ("dialogue", "let's discuss", "let's talk through this")
- Task lacks detail or has meaningful ambiguity
- Scope is large enough that assumptions could lead to significant rework

**Dialogue vs. planning:**
- **Dialogue:** "Do we fully understand what we're building?"
- **Planning:** "How do we build this thing we understand?"

Dialogue can precede planning, follow planning (to refine), or stand alone.

**Anti-pattern this prevents:** charging ahead with a plan based on incomplete information, forcing the model to guess at requirements and potentially build the wrong thing.

## Emphasis on Parallelizing Work

You can spawn up to 10 agents simultaneously. When a task is parallelizable, divide it into up to 10 approximately equal **buckets of work** (by complexity, not file count). Buckets must be independent. Agents stepping on each other is worse than under-parallelizing.

**Proactively parallelize** when work is independent. Don't ask, just split and go. Examples: fixing multiple failing tests, adding tests for several components, updating independent files with similar changes, batch operations on independent items.

**Example:** "Fix all 15 failing tests" → spawn 10 agents, each handling 1-2 tests by complexity.

**When NOT to parallelize:** shared mutable state, order-dependent operations, or agents that would edit the same files. When in doubt, fewer buckets.

## c11 (First-Class Environment)

[c11](https://github.com/Stage-11-Agentics/c11) is a native macOS terminal multiplexer built on Ghostty's renderer. Primary workspace environment. **Assume you are running inside c11 unless detection says otherwise.**

**Load the `c11` skill whenever ANY of these is true:**
- `C11_SHELL_INTEGRATION=1` or any `C11_*` env var is set (you're running inside c11)
- The operator says "c11" or "cmux", or asks about workspaces, areas, tabs, splits, or the embedded browser
- The task touches terminal multiplexing, sub-agent orchestration in sibling areas, or multi-area layout

The skill owns splits, sends, sub-agent orchestration, the embedded browser, targeting rules, tab naming, area resize, and sidebar reporting. **Do not improvise `c11` commands from memory.** The skill is kept current with binary quirks the help output doesn't surface. Do not reach for Chrome MCP when you're in c11.

**Tab naming is mandatory and must happen first.** When running inside c11 (`C11_SHELL_INTEGRATION=1`), your very first batch of tool calls must include: `c11 rename-tab --tab "$C11_TAB_ID" "<role>"`. An unnamed tab gets Claude Code's auto-title from the first user message, which produces names like "✳ Read and follow implementation prompt instructions". Useless for navigation. Key first, 2-4 words, under 25 chars.

## Git: Auto-Commit and Push Policy

**Auto-commit is ON by default.** When a discrete unit of work is complete (feature, fix, review pass, refactor), commit it immediately. Don't wait for the operator to say "commit." Group related changes into logical commits with good messages, the same quality as if asked explicitly.

**Get work to a finished state. Push ahead when the path is clear.** The goal is to leave work landed, not pending approval. When you've completed a logical unit on a feature branch (committed, build green, tests where applicable), push it. Open the PR if one is warranted. Don't stop short at "changes are committed locally" when the obvious next step is `git push`.

**Confirm when the path is genuinely ambiguous.** Force-pushing over shared history, pushing directly to `main`/`master` on a repo with collaborators, or pushing unvalidated work all warrant a check-in. Spirit: act decisively on clear forward motion, pause when the action is hard to reverse or affects others' work.

## Environment Confirmation

Before running any command that affects data or server state, confirm the target environment:
- "This will run against [dev/prod/local]. Is that correct?"
- Never assume. Explicit confirmation prevents costly mistakes.

## AskUserQuestion Best Practices

When using `AskUserQuestion` for non-trivial decisions (anything beyond simple yes/no or cut-and-dried choices):

- **Include pros and cons** for each option. The operator benefits from seeing tradeoffs surfaced explicitly rather than having to reason through them independently.
- **State a recommendation** if you have a clear preference. Lead with the recommended option (mark it with "(Recommended)") and explain *why*. The operator can always override.
- **Keep it proportional.** Simple factual questions ("Which file?", "TypeScript or Python?") don't need pros/cons. Just present the options. Reserve detailed treatment for architectural choices and tradeoff-heavy decisions.
- **Ask as many questions as needed.** Up to 5 per round; 10+ across rounds is fine. Don't compress at the cost of clarity.
- **Use rich descriptions.** For complex choices, several sentences per option is encouraged. A well-explained option beats a terse one-liner that leaves the operator guessing.

## Recognizing Thrashing

If you notice repeated failed attempts at the same bug (3+ tries), circular debugging, or operator frustration:

1. **Pause and acknowledge:** "This isn't going as intended. We may be thrashing."
2. **Generate a fresh handoff prompt** for a new agentic session containing:
   - **Actions taken:** what we tried and why it didn't work
   - **Current state:** relevant file states, error messages, test output
   - **Observed behavior:** what's actually happening vs. expected
   - **Possible directions** (non-exhaustive): a few hypotheses, framed openly, not as "the answer"

Fresh context without accumulated assumptions often breaks through stuck situations.

## Self-Improvement

If you notice a pattern, convention, or piece of knowledge that would help future sessions, suggest adding it to the relevant `CLAUDE.md` file. Every future session (yours and other agents) reads these files first. A 30-second addition here can save hours across the team of agents and humans who would otherwise rediscover the same thing.
