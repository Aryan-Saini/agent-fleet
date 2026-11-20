---
name: recall
description: "Reconstruct your recent working context from your own chat history, live state, and the shared record (user reports, prior fixes, incidents), then hand back a tight current-state brief. Use for 'recall my work on X', 'catch me up', 'what have I been working on', 'where did I leave off', before starting or resuming work."
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "nothing to run. Reads local chat transcripts and runs git/gh"
---

> Derived from the `recall` skill in Lauren Tan's [pstack](https://github.com/cursor/plugins/tree/main/pstack/skills/recall),
> MIT licensed (see `LICENSE` in this folder). Local changes: transcript paths for every
> harness, T3 Code threads as the first source, and the `metadata` block.

# Recall

**Before you start or resume work, rebuild the user's recent working context and hand back a tight capsule of where things stand now and what to do next.**

Keep it tight and on-topic. Read only what the in-scope threads need, then stop. The heavy reading fans out to parallel subagents. The main thread keeps only their findings and the final brief.

Your context lives in two records. Your own chat history holds what you did and decided. The shared record holds everything that happened around the same code under other names: the symptoms users keep reporting, the fixes that shipped and got reverted, the errors still firing in prod. That second record lives in source control, the issue tracker, chat channels, long-form docs, and error tracking. A feature with a long bug tail keeps most of its story there, so don't reconstruct it from your transcripts alone.

## Where the chat history is

| Harness | Transcripts |
| --- | --- |
| Claude Code | `~/.claude/projects/<slug>/<uuid>.jsonl`, subagent runs in `<uuid>/subagents/`. Typed prompts across all projects: `~/.claude/history.jsonl` |
| Cursor | `~/.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>.jsonl` |
| Codex | `~/.codex/sessions/<yyyy>/<mm>/<dd>/*.jsonl` |

`<slug>` is the workspace path with every "/" turned into "-". Claude Code keeps the leading one (`/home/you/proj` becomes `-home-you-proj`), Cursor drops it (`home-you-proj`). Every line of a transcript is one chat message.

Inside T3 Code, start with T3's own threads instead. They cover every provider in one place, and every linked machine: `t3_thread_search` and `t3_thread_list` to find threads, `t3_thread_read` to read them (`afterPosition` reads incrementally, the `activity` view adds tool calls). Each linked machine has its own T3 MCP server (for example `t3-code` for the controller and `t3-<worker>` for a worker). Fall back to the transcript files outside T3, or when you need a subagent's internals.

Skip `subagents/` files unless the question is what a subagent actually did. They are noise for ordinary recall and they outnumber the main sessions.

## Steps

1. **Classify, then route.** Resuming one specific prior chat is a different job: open that chat. A human-readable summary of your week is a different task. Recall loads working context across recent chats before you act. If the user already gave you a full state capsule (paths, branch, the change), use it and skip the mining.
2. **Lock the scope before searching.** Pin the window ("recent" is a real range, default the last 7 days), the topic if named, and the workspace (default the active one; never read another project's transcripts without being asked). State the scope back. Never quietly turn "all" into "recent N".
3. **Fan out across your chat history.** Spawn parallel subagents on a fast, cheap model, each taking a slice of the corpus. Tell every subagent to order candidates by real modification time (`ls -t`), never by UUID name, to grep the topic first and read only the matching chats and only their relevant regions, and to skip the current chat plus obvious noise (subagent, eval, and test chats). Each returns one block per chat: topic, the user's goal, decisions, open threads, struggles and corrections, and artifacts (PRs, tickets, branches), each citing the chat UUID. For one or two chats, skip the fan-out and search directly.
4. **Sweep the shared record** whenever the topic names a feature, file, subsystem, or bug. This is the default, and "my work on X" does not exempt it. Run one investigator per source (git log and blame, PRs, the issue tracker, error tracking, team chat) in parallel with the chat mining. Ask each: what is the current state, what has been tried and didn't hold, what are users still reporting. A null result is a finding. Skip an unavailable source and say so. Skip this step only for pure activity recall with no named target ("what did I do this week").
5. **Verify against live state.** A transcript or a stale ticket is history, not current truth. Check every PR, branch and ticket the mining surfaced with `git` and `gh`. When the answer hinges on what an agent actually did (tools it ran, files it read, errors it hit), read the full transcript.
6. **Write the brief** to the contract below. Group by thread. Stay on the named topic.

## Output contract

Lead with the capsule, then thread status, then problems, then the next move. Deeper detail goes below or gets cut.

- **Capsule.** At most 5 bullets. What this work is and where it stands overall.
- **Threads.** One line each, with exactly one status tag: `[merged #N]`, `[open PR #N]`, `[in flight <branch>]`, `[verified, uncommitted]`, `[reverted #N]`, or `[planned, not started]`. A thread with no tag is not done yet, so tag it.
- **Problems.** At most 5, the recurring ones. Include symptoms users keep reporting and any fix that shipped and was reverted, so the next attempt starts where the last one failed.
- **Next move.** The single most useful next action, concrete.

An adjacent feature stays out unless it blocks this one. When the brief outgrows a screen, cut detail before you cut threads. Write it through the **unslop** skill. Cite chat findings by UUID and shared-record findings by source (PR #, ticket ID, chat permalink, error-tracker issue). Strip private context before any public output.
