# Runs Ledger — lattice-orchestrator

The run log behind the skill's rules. Each entry preserves the story that shaped (or validated) a rule; the skill itself carries only the timeless statement. New entries accrue at closeout audits; a footgun mitigated three times in one run, or seen across two runs, promotes to a permanent rule in the references with its story recorded here.

This separation is the point, and it is the part worth copying: **the rule lives in the skill, the story lives here.** A skill that carries its war stories inline grows unreadable and stops being loaded; a skill that discards them loses the evidence for its own rules and gets "simplified" by the next operator who doesn't know why a line is there. Two files, two jobs.

The promotion path:

1. A run hits a new silent-failure mode. It goes into that run's `run-state.md` under `## Run-time footguns` — symptom → cause → mitigation — and the mitigation is folded into every subsequent boot prompt *in that run*. (A catalog entry without a prompt update guarantees the next delegator hits the same wall.)
2. At closeout, the audit reads the run's comments, commits, and archived-agent notes and asks which footguns were *timeless* rather than incidental to that codebase.
3. Mitigated three times in one run, or seen across two runs → it becomes a permanent rule in `SKILL.md` or the relevant `references/*.md`, stated once, in the imperative. The story that earned it lands here, dated, with the ticket IDs that produced it.

Entry shape — one section per run, bullets per lesson, each bullet naming the failure and the rule it produced:

```markdown
## <Run name> (<date>)

- **<Rule name>:** <what actually went wrong, concretely — the command, the symptom,
  how it was caught, what it cost>. Promoted to <the rule that now exists because of it>.
```

Stage 11's live ledger is kept with the private skill tree; the entries name internal projects, so this published copy ships the pattern rather than the history. Start your own — the first three entries will teach you more about your fleet than any amount of reading about someone else's.
