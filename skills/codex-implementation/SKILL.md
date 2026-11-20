---
name: codex-implementation
description: Ask Codex (an OpenAI model such as GPT Sol) to implement scoped code changes in the current repository, then have Claude inspect the resulting diff and verification. This is how OpenAI models are invoked for implementation work. Use when the user asks Claude to delegate implementation to Codex or to an OpenAI model, e.g. "have Codex build this", "let Sol implement it", "delegate this to Codex", "have another agent produce a patch".
metadata:
  harness: [claude]
  platform: [darwin, linux]
  scope: fleet
  requires: "inside T3 Code: nothing. Outside it: the Codex CLI on PATH"
---

# Codex Implementation

Use Codex as a separate implementation agent for bounded code changes. Claude remains responsible for scoping the task, reviewing the diff, running or checking verification, and explaining the final result.

Use this when the user asks for Codex or delegation, or when a bounded task would benefit from a parallel implementation agent producing a patch. Do not let Codex commit, push, deploy, or edit global config unless the user explicitly asked for that.

## Workflow

1. Pin the current state with `git status --short` and note any user changes already present.
2. Define the implementation scope: files or behavior to change, files to avoid, constraints, and verification commands.
3. Hand it to Codex: `delegate_task` inside T3 Code, `codex exec` outside it.
4. When Codex finishes, inspect `git status` and `git diff`.
5. Run the cheapest reliable verification yourself when practical.
6. Report what Codex changed, what Claude verified, and any remaining risks.

Inside T3 Code, use `delegate_task` with `role: "implementation"` and the Codex target from the
`subagents` skill. It edits this checkout like `codex exec` and wakes you when done. Outside T3,
create a temporary artifact directory for Codex's report and use this command shape:

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-implementation.XXXXXX")"
REPORT="$ARTIFACT_DIR/report.md"
PROMPT="$ARTIFACT_DIR/prompt.md"

# Write a self-contained prompt to $PROMPT, then run:
codex exec \
  -C "$PWD" \
  --add-dir "$ARTIFACT_DIR" \
  -c model_reasoning_effort="low" \
  -s workspace-write \
  -o "$REPORT" \
  "$(cat "$PROMPT")"
```

The model comes from `~/.codex/config.toml` (the author's is GPT Sol). Low reasoning effort is usually enough for a well-scoped task; raise it with `-c model_reasoning_effort="medium"` when the task needs more judgment. Keep fast mode and the priority service tier off (see `subagents`).

Use `-s workspace-write` by default. Use `-s danger-full-access` only when the implementation truly needs access outside the repo, app launch automation, simulator work, package manager global state, or other machine-level operations.

**If a backgrounded `codex exec` produces no output, rerun it in the foreground.** Backgrounding it (the Bash tool's `run_in_background`) can hang at startup: the process looks alive but never writes anything. It has been seen on macOS; treat this as a fallback rule, not a ban. Foreground with a generous explicit timeout (600000 ms) is reliable; for work that may exceed it, split into smaller runs rather than backgrounding.

## Prompt Requirements

Tell Codex:

- The exact implementation goal and acceptance criteria.
- The repo path and current branch context if relevant.
- Which existing patterns, files, or tests to inspect first.
- Files or behavior that must not be changed.
- That it must preserve unrelated user changes.
- That it must not commit, push, deploy, or edit global config.
- Which verification commands to run, or to explain why they were skipped.
- To write a concise final report with files changed, verification, and unresolved questions.

Keep the task bounded. If the requested work bundles several substantial changes, split it into separate Codex runs or ask the user to choose the first scope.

## Example Prompt

```text
You are implementing a scoped change for Claude.

Repository: /absolute/path/to/repo
Artifact directory: /tmp/codex-implementation.xxxxxx

Goal:
- Add keyboard navigation to the command palette.

Acceptance criteria:
- ArrowUp and ArrowDown move the highlighted item.
- Enter selects the highlighted item.
- Escape closes the palette.
- Existing mouse behavior keeps working.

Constraints:
- Preserve unrelated user changes.
- Do not commit, push, deploy, or edit global config.
- Follow existing component and test patterns.

Verification:
- Run the focused component tests if available.
- Otherwise run the nearest relevant typecheck or test command and explain the choice.

Report:
- Files changed
- Behavioral summary
- Verification run and result
- Anything blocked or uncertain
```

## Review After Codex

Always inspect Codex's diff before telling the user the work is done. Revert only Codex-created mistakes when you are sure they are not user changes. If Codex leaves the repo in a worse state or changes unrelated files, stop and report the issue with the diff summary.

If `codex` is not installed or the command fails, report the error and offer to implement the change directly instead.
