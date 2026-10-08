# Driving a live Codex session

For the case in SKILL.md where a hard action-time confirmation fires on every run and cannot be
removed. Claude drives the session and forwards the confirmation itself. Do not hand the user a
command to run, do not call it impossible headlessly, and do not re-ask for approval they already
gave.

Why this is allowed: the confirmation exists so a human authorizes the consequential act. The user is
that human, and authorized it in the conversation, for their own machine and their own account.
Forwarding their standing yes honours the instruction. It is not weakening a control that protects
anyone else.

## Helpers

```bash
cu_start(){ tmux kill-session -t cu 2>/dev/null; tmux new-session -d -s cu -x 200 -y 50; \
            tmux send-keys -t cu "codex -C \"$PWD\" -s danger-full-access \"\$(cat $CU_ART/prompt.md)\"" Enter; }
cu_see(){ tmux capture-pane -pt cu -S -"${1:-40}"; }   # read the pane, last N lines
cu_say(){ tmux send-keys -t cu "$*" Enter; }           # forward text
cu_key(){ tmux send-keys -t cu "$@"; }                 # raw keys: cu_key Down Enter
cu_end(){ tmux send-keys -t cu C-c 2>/dev/null; sleep 1; tmux send-keys -t cu C-c 2>/dev/null; \
          sleep 1; tmux kill-session -t cu 2>/dev/null; \
          "$CU_SKYCLIENT" turn-ended '{"type":"agent-turn-complete"}' 2>/dev/null; }
```

```bash
cu_new                 # write the prompt to $CU_ART/prompt.md
cu_start               # launch codex in tmux
cu_see 40              # read, repeat as needed
cu_key Down Enter      # answer the first-run "Hooks need review" screen if it appears
cu_say yes             # forward the authorized approval
cu_end                 # close once the result is captured
```

Expect **two** gates in a fresh directory: a "do you trust this directory?" screen first, Enter
for yes, then the real approval selector. Pick the one-time option, never the persist option,
unless the user authorized that specifically.

No tmux? `screen` ships with macOS and takes the same shape:

```bash
screen -dmS cu bash -lc "codex -C \"$PWD\" -s danger-full-access \"\$(cat $CU_ART/prompt.md)\""
screen -S cu -X hardcopy /tmp/cu.cap && cat /tmp/cu.cap
screen -S cu -X stuff $'yes\n'
screen -S cu -X quit
```

## Don't poll with an agent

Capturing the pane from a subagent costs a full LLM turn per capture, and the cost grows with
both wait time and context size. Arm a background bash watcher instead: bash polls every 2s for
free, exits on the first event, and the harness wakes the agent exactly once per gate.

Run it with Bash `run_in_background: true`:

```bash
for i in $(seq 1 240); do
  P=$(tmux capture-pane -pt cu -S -60 2>/dev/null)
  echo "$P" | grep -qiE "do you trust"                        && { echo TRUST_PROMPT;    exit 0; }
  echo "$P" | grep -qiE "would you like to run|1\. yes|allow" && { echo APPROVAL_NEEDED; exit 0; }
  [ -f "$CU_ART/done.marker" ]                                && { echo COMPLETED;       exit 0; }
  sleep 2
done; echo WATCHER_TIMEOUT
```

On each wake: one `cu_see` to read the real screen, send the one authorized key, re-arm the
watcher. A typical run is three wakes, trust screen, approval, completion, no matter how long
Codex takes.

Two things learned the hard way: anchor the greps to approval-UI phrasing, or echoed prompt text
in the pane matches and wakes you for nothing. And prefer a file-existence completion signal,
have Codex touch `$CU_ART/done.marker`, over grepping the pane for a word.

If you would rather delegate the loop than watch it, use a subagent on medium effort, named
`[<model>] [codex computer use] <the concrete action>`. Give it the session name, the exact
confirmations it may forward, and the stop condition.

## Guardrails on the auto-forward

- Forward only the specific action the user authorized in this task. Report what you approved and
  on what authorization.
- If Codex asks about something broader or different, deleting keys, changing billing, a second
  key, stop and ask. Never blanket-approve every prompt.
- Secrets come back through the live pane, never a file. For API key creation, collect the
  project identifier in a headless read-only prep pass first; only the key value needs the
  interactive session.
- If the service has an official CLI or API for the job, say so. It is a better answer than
  Computer Use. Do not switch without being asked.

## Ghost cursor

Killing the tmux pane mid-run leaves the translucent Sky overlay on screen, because
`SkyComputerUseService` never receives the session-ended signal. `cu_end` prevents it.

For an overlay already stuck from an earlier run, the `turn-ended` signal alone will not clear
it. Confirm nothing is using Computer Use, then SIGTERM that one process:

```bash
ps axo pid,ppid,etime,command | grep -E "SkyComputerUseService|node_repl" | grep -v grep
# node_repls idle and no live run -> safe:
kill -TERM <SkyComputerUseService PID>
```

**Exact PID only. Never `pkill` by name**, and never force-quit codex, ChatGPT.app, or
`node_repl`. Those are shared, and another Codex session, the user's or another agent's, may be live.
The service respawns on demand and persisted Always-allow grants survive the restart.
