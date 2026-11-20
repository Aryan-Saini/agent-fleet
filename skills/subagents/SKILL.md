---
name: subagents
description: When using subagents, fanning work out in parallel, delegating to another model or harness (Claude Code, Codex, opencode), calling T3 Code's delegate_task, picking a model and effort (Opus, Fable, GPT Sol, Haiku, Luna or your own), running a subagent on another machine, or getting one model or a council of them to review a diff, branch, commit or feature. The Council. READ THIS before delegating.
metadata:
  harness: [claude, codex, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "inside T3 Code: nothing. Outside it: the Codex CLI for OpenAI models; the opencode CLI for open-weight models through OpenRouter"
---

# Subagents and the council

## Titles show the model

Every subagent's title (`description` for the Agent tool, `title` for `delegate_task`) starts with
the model id and effort actually doing the work, in square brackets: `[opus-5.5 Medium] review
auth flow`, `[haiku-5.5] find callers`. A thin Claude wrapper that shells out to another harness
carries both: `[opus-5.5 Low] [gpt-6.1-sol Low] implement pagination`. Anyone reading the session
list knows what ran and what it cost.

## Rank your models, then route by the ranking

Name one **default**: what "a subagent" means when nobody names a model. Every other model is an
exception with a reason. Score every model you can reach, higher is better. **Ceiling** is how
good it is at its best, **floor** how bad it gets at its worst, **taste** covers UI, code quality,
API design and copy. Note what you pay next to the table: a flat subscription you under-use is
cheap, per-token billing is not.

The author's table, on one Claude subscription (Opus, Fable, Haiku) and two Codex ones (Sol,
Luna). Copy the shape, replace the rows with yours:

| model | ceiling | floor | taste | role |
| --- | --- | --- | --- | --- |
| opus-5.5 | 8.5 | 8 | 7 | **default**, every subagent |
| fable-5.2 | 10 | 9 | 9 | super reviews, the hardest 1% |
| gpt-6.1-sol | 7.5 | 4 | 6 | reviews |
| haiku-5.5 | 5 | 5 | 4 | file search, lookups, history audits |
| gpt-6-luna | 4.5 | 4 | 4 | bulk passes |

| job | pick | escalate to |
| --- | --- | --- |
| anything not listed | Opus Medium | Opus High |
| find files, search history, audits | Haiku | Opus Medium |
| bulk mechanical work, data passes | Luna High | Haiku |
| review a plan, diff or bug | Sol Medium | Sol High |
| super review (big, risky, hard to undo), or Opus High fell short | Fable Medium | top effort |

How to apply it:

- A wide gap between ceiling and floor means someone checks the output before anyone acts on it.
  That is why Sol reviews and does not work unsupervised.
- Effort defaults to Medium or High. Low where the table says so, xhigh when a run needs it.
  Never max, on any model.
- These are defaults, not limits. If the output misses the bar, step up one rung and redo it
  without asking. Escalating costs less than shipping mediocre work.
- Claude models run through the Agent tool's `model` parameter. OpenAI models go through Codex:
  `delegate_task` inside T3, the wrapper below outside it.
- Computer use is not delegated. The agent drives the screen itself through the
  `control-computer` skill.

## Never use fast mode

Fast mode stays off everywhere. Never run `/fast`, never pass `-c features.fast_mode=true` or
`-c service_tier="priority"`, never flip `fastMode` in Claude settings, never set `fastMode` or
`serviceTier: "priority"` on a T3 target. It burns subscription limits several times faster for
a latency win nobody asked for.

## Inside T3 Code

When the `t3-code` MCP tools are present: Claude to Claude on this machine is the native Agent
tool. Anything else (another vendor, another machine, or work that should show in T3 and on the
phone) is `delegate_task` with a `target`:

| model | `target` |
| --- | --- |
| Opus | `{"providerInstanceId":"claudeAgent","model":"claude-opus-5-5","options":{"effort":"medium"}}` |
| Fable | `{"providerInstanceId":"claudeAgent","model":"claude-fable-5-2","options":{"effort":"medium"}}` |
| Haiku | `{"providerInstanceId":"claudeAgent","model":"claude-haiku-5-5"}` |
| Sol | `{"providerInstanceId":"codex","model":"gpt-6.1-sol","options":{"reasoningEffort":"low"}}` |
| Luna | `{"providerInstanceId":"codex","model":"gpt-6-luna","options":{"reasoningEffort":"high"}}` |

`orchestrator_capabilities` lists the providers and model ids this install actually has. If an id
stops working, look there.

- The child sees only the task. Make it self-contained: repo path, goal, what not to touch, how
  to verify, what to report.
- Start it and end your turn; its completion wakes you. No polling.
- Parallel children that edit need `isolation: "worktree"`. It starts from the last commit, so
  commit first.
- To keep a child read-only, say so in the task. Don't narrow `runtimeMode`: it stalls on
  approvals nobody sees.

### A subagent on another machine

"Run this on the worker", "subagent on the controller", or an `@<machine>` chip means
`delegate_task` with `environmentId` added to the model's `target`. It shows as a subagent card
and wakes you like a local child.

| machine | `environmentId` |
| --- | --- |
| `<worker>` | `<worker-environment-uuid>` |
| `<controller>` | `<controller-environment-uuid>` |

`t3_environment_links` lists linked machines and their ids; paste yours into this table. A
top-level thread over there, or moving this thread's changes, is the **t3-environment-handoff**
skill.

## Other harnesses, outside T3

A workflow or subagent's model parameter only takes Claude models. To use another vendor, spawn a
thin Claude wrapper (`model: opus`, `effort: low`) whose only job is to write a self-contained
prompt, run the other CLI through Bash, and return its report (give the wrapper a `schema` for
structured output).

**Codex.** Put your default model and effort in `~/.codex/config.toml` so a bare run is the one
you want. Override per run:

```bash
codex exec -C "$PWD" -s read-only -o "$REPORT" "$(cat "$PROMPT")" </dev/null                  # default (Sol Low)
codex exec -c model="gpt-6-luna" -c model_reasoning_effort="high" -C "$PWD" -s read-only ...   # Luna
```

**opencode**, for open-weight models through OpenRouter:

```bash
opencode run --dir "$PWD" -m openrouter/<provider>/<model> "<self-contained prompt>"
```

- The other harness does not read CLAUDE.md. Put everything it needs in the prompt.
- Runs can outlast a 10 minute tool timeout. Pass an explicit timeout, or run in the background
  and wait for the report file.
- Parallel agents that edit code each get their own git worktree, or they collide.
- Workflow token budgets count only Claude tokens; Codex work is invisible to them.

For implementation, use the **codex-implementation** skill.

## The council: independent review

Use another model as a reviewer when the user asks for a second pass or a change is broad.
Don't delegate review to avoid reading the code yourself. Treat every reviewer's output as
evidence, not authority.

1. Pick the target: uncommitted changes, branch vs base, one commit, or files.
2. Make an artifact dir: `ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review.XXXXXX")"`.
3. Run each reviewer with the prompt below.
4. Verify every claimed finding against the code before relaying it.

**The Council** is Sol Medium + Opus High by default, plus Fable Medium for a super review. Two
vendors means the reviewers don't share the author's blind spots.

**Inside T3**, each reviewer is its own `delegate_task` with `role: "review"`, carrying the repo
path, the target (`git diff HEAD`, `git diff main...`, `git show <sha>`) and the prompt. A second
round is a new `delegate_task` with the original brief, prior findings, responses and unresolved
objections, never a message to the old child's thread.

**Outside T3:**

```bash
codex -C "$PWD" -c model_reasoning_effort="medium" review --uncommitted - < "$PROMPT" > "$REPORT"
codex -C "$PWD" -c model_reasoning_effort="medium" review --base main - < "$PROMPT" > "$REPORT"
codex -C "$PWD" -c model_reasoning_effort="medium" review --commit <sha> - < "$PROMPT" > "$REPORT"
```

For Opus or Fable, spawn a subagent with `model` set and the target in the prompt
(`[fable-5.2 Medium] review <target>`); it runs git itself.

The review prompt:

```text
Review these changes for bugs, regressions, missing tests, security issues, and requirement
mismatches. Prioritize findings over summary. For each finding include severity, file and line,
the concrete failure mode, and a suggested fix direction. Do not edit files. If there are no
substantive findings, say so and name any residual test gaps.
```

Report confirmed issues separately from unverified suggestions. If a reviewer found nothing, say
so and name what it inspected. If a CLI is missing or fails, report the error and offer to review
directly.
