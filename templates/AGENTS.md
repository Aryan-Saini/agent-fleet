<!--
rules/AGENTS.md: global rules for every harness that follows the agents.md standard.
fleet link puts it at ~/.codex/AGENTS.md (Codex, and opencode by reference) and generates
~/.cursor/rules/fleet-global.mdc from it (Cursor). Claude reads it through rules/CLAUDE.md.
Keep it harness-neutral: anything only one harness understands goes in that harness's file.
Replace every <placeholder>. Delete what you disagree with. These are defaults, not laws.
-->

I'm <your name>. Address me as "<name>".

<One or two lines on what you do and what you build. Agents calibrate on this.>

Email for work: <work email>. Personal: <personal email>, only for non-work things. Use these over
any email the harness injects.

# Coding

- Keep things simple. YAGNI unless told otherwise.
- Type safety is useful. Use it. No `any`.
- Propose bold ideas when they meaningfully help.
- Be careful with destructive actions that were not explicitly requested.
- Tests should be focused. No smoke-test sprawl, no tests that only prove a deletion happened.
- Comment why, above functions and modules. Keep comments in sync with the code.
- Default stack when a project has none: <e.g. TypeScript, React, Tailwind, pnpm>.

# Questions are read-only

- A question is a request for an answer, not for changes. "How hard would it be", "why does",
  "should we", "can X do Y": answer it, do not edit files.
- If the change is obvious and trivial, answer first and offer it. Ask before making it.

# Match ceremony to the task

- Do not spawn subagents for work one agent finishes in one pass. Delegation is for breadth or
  for adversarial review.
- When several agents work in parallel, state file ownership up front so they do not collide.
- If asked to do too much at once, stop and say so.

# Blast radius

- Never touch production, live databases or daily-driver build channels unless told to. When a
  task is adjacent to one, name what you are about to touch before touching it.
- Reading data, and building ways to read it, needs no permission.

# Pull requests

- Follow the repo's title conventions; conventional commits where the repo uses them.
- Open the description with the problem in plain words, then how it was solved.
- End with one line naming the model and harness that made the change.
- Open a real PR, not a draft. Rebase onto the latest main first.
- Merge only when the request says to.

# Writing

- No em dashes. Sentence case headings. Plain words. The `unslop` skill applies to everything.

# The fleet

- Run `fleet` to learn which machine you are on and its role. `computers.md` in the fleet repo
  is the map; read it before reaching for another machine.
- Config (these rules, skills, the fleet repo) is authored on the controller only. On a worker
  your edits to them are discarded by the next sync. Make the change on the controller.
- Files cross machines through `~/drop` (Syncthing) or `fleet send <machine> <file>`. Images
  cannot be pasted over ssh; reference them by path.
- Long jobs on a worker run in tmux. Disruptive work runs as `fleet workorder`, never over a live
  ssh session.
- When a long job finishes, needs a decision, or breaks unattended: `fleet alert "title" "msg"`.
