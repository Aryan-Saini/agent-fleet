# peekaboo

[Peekaboo](https://github.com/steipete/Peekaboo) is a macOS CLI that lets an agent see the screen
and click, type and press keys with real input events. Any harness can drive it from a shell,
so GUI work does not depend on one vendor's computer-use feature.

How it fits: the `control-computer` skill routes GUI work cheapest first. A shell command beats
a CLI beats reading a browser with osascript beats driving the screen. When the screen is the
only way, it uses a computer-use agent (Codex Computer Use) by default and Peekaboo when you ask
for it or that agent is out of usage. The details and traps are in
`skills-controller/control-computer/references/peekaboo.md`.

## Install

```bash
brew install steipete/tap/peekaboo
peekaboo permissions status        # Screen Recording + Accessibility
```

Run it from the terminal app your agent runs in, so it inherits that app's Screen Recording and
Accessibility grants and nothing prompts mid-task. If you build from source, sign the binary with
a stable identity or macOS drops the grants on every rebuild.

## Verify

```bash
peekaboo see --no-elements --path /tmp/peek.png && echo ok
```

## Updating

Homebrew installs: `brew upgrade peekaboo`. Commands move between major versions; `peekaboo learn`
prints the current guide.

## Other OSes

The skill's routing table is OS-neutral. On Linux desktops `xdotool` plus a screenshot tool fill
the same slot; on Windows, an automation CLI does. Port the reference, keep the routing.
