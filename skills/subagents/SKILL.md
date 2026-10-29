---
name: subagents
description: When using subagents, fanning work out in parallel, delegating to another model or harness like Codex, opencode or Claude Code, calling T3 Code's delegate_task, picking a model and effort for a job, running a subagent on another machine, or getting one model or a council of several to review a diff, branch, commit or feature. READ THIS before delegating.
metadata:
  harness: [claude, codex, opencode]
  platform: [darwin, linux]
  requires: "inside T3 Code: nothing. Outside it: the Codex CLI for OpenAI models; the opencode CLI for open-weight models through OpenRouter"
---

# Subagents and the council

## Titles show the model

Every subagent's title starts with the model and effort actually doing the work, in square
brackets: `[opus Medium] review auth flow`. A thin Claude wrapper that shells out to another
harness carries both: `[opus Low] [codex High] implement pagination`. Anyone reading the session
list knows what ran and what it cost.

## Rank your models, then route by the ranking

Name one **default** model: what "a subagent" means when nobody names a model. Every other model
is an exception with a reason.

Then score every model you can reach, higher is better. **Ceiling** is how good it is at its
best. **Floor** is how bad it gets at its worst. **Taste** is UI, code quality, API design and
copy. Note what you pay next to the table: a flat subscription you are under-using is cheap,
per-token billing is not.

Example, the shape of the author's table. Replace it with yours:

| model | ceiling | floor | taste | role |
| --- | --- | --- | --- | --- |
| Claude Opus | 8.5 | 8 | 7 | default, every subagent |
| top Claude model | 10 | 9 | 9 | super reviews, the hardest 1% |
| frontier OpenAI model | 7.5 | 4 | 6 | reviews, computer use flows |
| Claude Haiku | 5 | 5 | 4 | file search, lookups, history audits |
| small OpenAI model | 4.5 | 4 | 4 | bulk passes, one-step computer use |

Then route jobs to it:

| job | pick | escalate to |
| --- | --- | --- |
| anything not listed | default, Medium | default, High |
| find files, search history, audits | small Claude model | default |
| bulk mechanical work, data passes | cheapest model that clears the bar | small Claude model |
| review a plan, diff or bug | a model from another vendor | the same, High |
| super review (big, risky, hard to undo), or the default fell short | top model | top model, High |

How to apply it:

- A wide gap between ceiling and floor means someone checks the output before anyone acts on
  it. Those models review; they don't work unsupervised.
- These are defaults, not limits. If the output misses the bar, step up one rung and redo it
  without asking. Escalating costs less than shipping mediocre work.
- Anything user-facing (UI, copy, API design) needs real taste.
- Effort defaults to Medium or High. Low only where the table says so. Never max.

## Inside T3 Code

When the `t3-code` MCP tools are present, use the native subagent tool for Claude to Claude on
the same machine. For anything else (another vendor, another machine, or work that should show in
T3 and on your phone), use `delegate_task` with a `target`:

```json
{"providerInstanceId": "codex", "model": "<openai model id>", "options": {"reasoningEffort": "medium"}}
{"providerInstanceId": "claudeAgent", "model": "<claude model id>", "options": {"effort": "medium"}}
```

`orchestrator_capabilities` lists the providers and model ids this install actually has.

- The child sees only the task. Make it self-contained: repo path, goal, what not to touch, how
  to verify, what to report.
- Start it and end your turn; its completion wakes you. No polling.
- Parallel children that edit need `isolation: "worktree"`. It starts from the last commit, so
  commit first.
- To keep a child read-only, say so in the task.
- **On another machine:** add that machine's `environmentId` to the `target`.
  `t3_environment_links` lists linked machines and their ids. It shows as a subagent card and
  wakes you like a local child.

## Other harnesses, outside T3

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

The default council is two reviewers from different vendors, plus your top model for a super
review. Inside T3, each reviewer is its own `delegate_task` with `role: "review"`. A second round
is a new `delegate_task` carrying the original brief, prior findings, responses and unresolved
objections, never a message to the old child's thread.

Outside T3:

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
