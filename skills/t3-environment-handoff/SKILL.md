---
name: t3-environment-handoff
description: Hand work off to the OTHER machine's T3 Code (controller to worker, or worker to controller) as a new thread there. Either start a fresh worktree from a base branch, or move the current checkout (branch, uncommitted and untracked changes) into a worktree over there and continue it. Use when the user says "environment handoff", "hand this off to the worker", "move this to the worker/the laptop", "run this on the worker in a new worktree", "continue this on the other machine", or wants work registered in the other machine's T3 so they can see it.
metadata:
  harness: [claude]
  platform: [darwin, linux]
  scope: fleet
  requires: "Claude Code signed in to the other machine's T3 MCP endpoint (a t3-<peer> server), ssh aliases both ways, tailscale and jq"
---

# T3 environment handoff

Like T3's own worktree handoff, but the new thread lands on the other machine. It is an ordinary
top-level thread in that machine's T3, so the user sees it in the app and on their phone. For a
subagent over there that reports back to you instead, use `delegate_task` with an
`environmentId` (the **subagents** skill).

Fill in your pair:

| you are on | other machine | MCP server | ssh alias |
| --- | --- | --- | --- |
| controller | worker | `t3-<worker>` | `<worker>` |
| worker | controller | `t3-<controller>` | `<controller>` |

## Setup, once per pair

Each machine's T3 Code serves MCP at its tailnet URL (`https://<machine>.<tailnet>.ts.net/mcp`).
Register it in Claude Code on the other machine and sign in:

```bash
claude mcp add --transport http --scope user t3-<peer> https://<peer>.<tailnet>.ts.net/mcp
claude mcp login t3-<peer>       # opens the browser; approve with a pairing code from the peer
```

On a headless worker, run the login with `--no-browser` in tmux and forward its callback port
from the laptop (`ssh -fN -L <port>:127.0.0.1:<port> <worker>`), then open the printed URL there.
These sign-ins expire after 30 days on current T3 builds. Renew them on a schedule (the
`fleet-update` skill's weekly peers step). Don't mint `t3 auth session` bearer tokens for this;
MCP rejects them.

## Pick the mode

- **Fresh**: new worktree from a base branch (default `main`). For new work: an audit, a feature,
  a fix.
- **Move**: take the current checkout and continue it over there: the branch's commits plus
  uncommitted and untracked changes. Gitignored files are not copied.

If the user didn't say, use Fresh when the work hasn't started and Move when there are commits or
edits on the current branch for this task. Ask only if it's genuinely unclear.

## Reaching the other T3

Use the MCP tools (`mcp__t3-<peer>__*`; load them with ToolSearch). If that server failed to
connect, `scripts/t3-remote <tool> '<json>'` calls the same tools with the existing sign-in over
the peer's tailnet IPv6 address, which gets around a missing Tailscale IPv4 route, the usual
reason the MCP connection times out. It needs `T3_PEER_SERVER`, `T3_PEER_HOST` and `T3_TAILNET`.

## Steps

1. `t3_project_list` on the other machine. Find the project whose `workspaceRoot` is this repo.
   Missing: stop and offer the **create-project** skill.
2. Write the brief. The new agent sees only this message: the repo, the goal, what's done (point
   at commits, files or PRs rather than restating them), decisions made and why, what's left,
   constraints (no prod, no push or PR unless the user said so), how to verify, what to report.
   Redact secrets.
3. Prepare the workspace:
   - **Fresh**: base branch on origin:
     `{"type":"worktree","baseRef":"main","branch":"<new-branch>","startFromOrigin":true}`. Only
     local: push it first with `git push <ssh-alias>:<workspaceRoot> <base>:refs/heads/<base>`,
     then `startFromOrigin:false`.
   - **Move**: `T3_PEER_SSH=<ssh-alias> scripts/move-worktree <workspaceRoot> [branch]` from the
     current checkout. It snapshots the working tree through a throwaway index (your index and
     files stay untouched), pushes straight to the other machine's repo over ssh, creates the
     worktree, re-applies the uncommitted changes, and runs the target's worktree setup script
     (env files, dependency install). The last line is the worktree path. Use
     `{"type":"existing_worktree","worktreePath":"<path>","branch":"<branch>"}`. A rejected push
     (diverged branch, or checked out over there): stop and report. Never force-push.
4. `t3_thread_launch` with `projectId`, a short `title`, the `workspaceStrategy`, the brief as
   `message` and `runtimeMode:"full-access"`. The model is whatever the user asked for, otherwise
   the default in **subagents**. Check the target's shape: some T3 builds want `options` as an
   array, e.g. `{"instanceId":"claudeAgent","model":"<model id>","options":[{"id":"effort","value":"medium"}]}`.
5. `t3_thread_read` once to confirm it's running on the expected branch and worktree.

## Report

The thread as `[title](t3-thread://v1/<threadId>)`, plus machine, worktree path, branch and model.
Nothing wakes you when the remote thread finishes, so say so and offer to check it with
`t3_thread_read`. After a Move the source checkout still has the same changes; offer to clean it
up rather than doing it unasked.
