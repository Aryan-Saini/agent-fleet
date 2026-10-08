---
name: subagents
description: When using subagents, fanning work out in parallel, delegating to another harness like Codex, opencode or Claude Code, picking a model and effort for a job, or getting one model or a council of several to review a diff, branch, commit or feature. READ THIS before delegating.
metadata:
  harness: [claude]
  platform: [darwin, linux]
  requires: "the Codex CLI for OpenAI models; the opencode CLI for open-weight models through OpenRouter"
---

# Subagents and the council

## Titles show the model

Every subagent's title starts with the model and effort actually doing the work, in square
brackets: `[opus Medium] review auth flow`. A thin Claude wrapper that shells out to another
harness carries both: `[opus Low] [codex High] implement pagination`. Anyone reading the session
list knows what ran and what it cost.

## Rank your models, then route by the ranking

Write down every model you can reach, scored on three axes, higher is better. **Cost is what you
actually pay** (a flat subscription you are under-using is cheap; per-token billing is not).
Intelligence is how hard a problem you can hand it unsupervised. Taste is UI, code quality, API
design and copy.

Example, the author's table at the time of writing. Replace it with yours:

| model | reached through | cost | intelligence | taste |
| --- | --- | --- | --- | --- |
| frontier OpenAI model | Codex CLI, two flat subscriptions | 6 | 8 | 6 |
| Claude Opus | Claude Code, flat subscription | 4 | 6 | 7 |
| top Claude model | Claude Code | 2 | 9 | 9 |
| fast open-weight model | opencode + OpenRouter, per token | 9 | 4 | 5 |

How to apply it:

- These are defaults, not limits. If a cheaper model's output misses the bar, redo it with a
  smarter one without asking. Escalating costs less than shipping mediocre work.
- Cost is a tie-breaker. For anything that ships: intelligence, then taste, then cost.
- Bulk and mechanical work with a clear spec: the cheapest model that clears the bar.
- Anything user-facing (UI, copy, API design) needs real taste.
- Reviews: your strongest model, plus a model from a different vendor as an independent check.
- Set a default reasoning effort per model and stick to it unless the task says otherwise.

## Other harnesses

A workflow or subagent's model parameter only takes Claude models. To use another vendor, spawn
a thin Claude wrapper (cheap model, low effort) whose only job is to write a self-contained
prompt, run the other CLI through Bash, and return its report.

**Codex:**

```bash
codex exec -C "$PWD" -s read-only -c model_reasoning_effort="low" -o "$REPORT" "$(cat "$PROMPT")" </dev/null
```

**opencode**, for open-weight models through OpenRouter:

```bash
opencode run --dir "$PWD" -m openrouter/<provider>/<model> "<self-contained prompt>"
```

- The other harness does not read CLAUDE.md. Put everything it needs in the prompt.
- Runs can outlast a 10 minute tool timeout. Pass an explicit timeout, or run in the background
  and wait for the report file.
- Parallel agents that edit code each get their own git worktree, or they collide.
- `--auto` style approve-everything flags only for sandboxed or read-only work, never on a
  checkout you care about.

## The council: independent review

Use another model as a reviewer when the user asks for a second pass or a change is broad.
Don't delegate review to avoid reading the code yourself. Treat every reviewer's output as
evidence, not authority.

1. Pick the target: uncommitted changes, branch vs base, one commit, or files.
2. Make an artifact dir: `ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review.XXXXXX")"`.
3. Run each reviewer with the prompt below.
4. Verify every claimed finding against the code before relaying it.

```bash
codex -C "$PWD" review --uncommitted - < "$PROMPT" > "$REPORT"     # Codex, uncommitted changes
codex -C "$PWD" review --base main - < "$PROMPT" > "$REPORT"       # Codex, branch vs main
git diff main... > "$DIFF" && opencode run --dir "$PWD" -m <model> -f "$DIFF" "$(cat "$PROMPT")" > "$REPORT"
```

For a Claude reviewer, spawn a subagent with the model set and the target in the prompt; it runs
git itself.

The review prompt:

```text
Review these changes for bugs, regressions, missing tests, security issues, and requirement
mismatches. Prioritize findings over summary. For each finding include severity, file and line,
the concrete failure mode, and a suggested fix direction. Do not edit files. If there are no
substantive findings, say so and name any residual test gaps.
```

Report back with confirmed issues separated from unverified suggestions. If a reviewer found
nothing, say so and name what it inspected. If a CLI is missing or fails, report the error and
offer to review directly.
