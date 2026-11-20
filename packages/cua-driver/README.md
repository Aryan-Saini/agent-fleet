# cua-driver

[Cua Driver](https://cua.ai/docs/cua-driver), from [trycua/cua](https://github.com/trycua/cua),
lets an agent operate native GUI apps in the background: read a window's accessibility tree, act
on elements by token, use exact window geometry or pixels when it must, and verify the result
from fresh state. On macOS it does this without stealing focus, so you keep typing in your editor
while an agent drives another app. It runs on Linux and Windows too.

It is the default route for GUI work in the `control-computer` skill
(`skills-controller/control-computer`), ahead of [peekaboo](../peekaboo/). That skill decides
*whether* to touch the screen at all; Cua Driver is *how*.

Two ways in, same daemon:

| | how | when |
| --- | --- | --- |
| CLI | `cua-driver call <tool> '<json>'`, `cua-driver list-tools`, `cua-driver describe <tool>` | the default: any harness with a shell |
| MCP | `cua-driver mcp` (stdio) | harnesses where native tool calls are nicer, such as Claude Code |

## Install

macOS, no admin rights needed:

```bash
/bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)"
cua-driver --version
cua-driver permissions grant      # walks you through both switches, then test-captures
cua-driver doctor
```

This installs `/Applications/CuaDriver.app` and a `cua-driver` CLI that points into it. Then wire
the MCP server and the skill pack into each harness:

```bash
cua-driver mcp-config --client claude     # prints the MCP config and installs the skill pack there
cua-driver mcp-config --client codex
cua-driver skills install                 # or: link the skill pack into every detected harness
```

For Claude Code the MCP entry is just `{"command": "<home>/.local/bin/cua-driver", "args": ["mcp"]}`
at user scope. It needs no key, so it can be global like the other keyless servers in
[mcp](../mcp/).

The skill pack is upstream's `cua-driver` skill (`SKILL.md` plus `MACOS.md`, `WORKFLOW.md`,
`BROWSER.md` and friends). It is vendored by `cua-driver skills install`, versioned with the
driver, and refreshed by `cua-driver skills update`. Don't copy it into your own skills repo;
link it, so it updates with the binary.

## Permissions

Two macOS approvals, for Cua Driver's own identity (`com.trycua.driver`), not your terminal's:

| permission | without it |
| --- | --- |
| Accessibility | no input and no element actions. Stop |
| Screen Recording | no screenshots or pixel actions. Tasks the accessibility tree can finish still work |

Because the grants belong to the app, they survive updates (the designated requirement names the
bundle id and the Developer ID team) and they don't leak to every script your terminal runs.
Agents must never click these prompts themselves unless you said so for that task. On a managed
fleet, push a PPPC profile from your MDM instead.

Telemetry is on by default. Turn it off once if you prefer: `cua-driver telemetry disable`.

## Verify

```bash
cua-driver status                          # daemon running, socket, permission mode
cua-driver permissions status --json       # read-only, never prompts
cua-driver call list_apps '{}'             # a real call through the daemon
```

## Health

`check.sh`, on a Mac with it installed: the daemon is up and holds both permissions. Report only.
A daemon started from a shell would run under the shell's identity and lose its grants, and a
missing permission needs you.

## Updating

```bash
cua-driver check-update       # read-only
cua-driver update --apply     # installs the latest release
cua-driver skills update      # the skill pack, to match
```

`/fleet-update` does this nightly on the controller. After an update, check both the binary
version and the running daemon (`cua-driver status`); an update that replaces the app makes the
old daemon exit. Read the release notes for anything about telemetry, permissions or new network
calls before applying, like any other update that runs with Accessibility rights.

## Gotchas

- **Never `open -a` an app the agent is about to drive.** Every form of `open` activates the
  target and steals focus. Use `launch_app` with the bundle id.
- **One controller per desktop.** Separate sessions don't isolate keyboard focus. Don't run two
  agents on the same screen.
- **Check permissions from the driver, not your terminal.** `cua-driver permissions status`
  answers for the app's identity; a terminal-based check answers for the terminal.
