# mac-automations

Every scheduled job on a Mac, through one dispatcher and one macOS permission granted once.
Adding a job is dropping a folder in. No new LaunchAgent, no new System Settings prompt.

## Why a dispatcher

The obvious way to schedule a script on macOS is a LaunchAgent per job. That breaks down fast:

- **Permissions.** A job that reads Mail, Messages, Safari history, `~/Library` or even
  `~/Desktop` needs Full Disk Access, and macOS attributes access to the *responsible process*.
  Each new job means another grant, and a grant given to `/bin/bash` would hand it to every
  script on the machine.
- **PATH.** launchd starts jobs with `/usr/bin:/bin:/usr/sbin:/sbin`. Each job then pins
  `/usr/local/bin/aws` or `~/.nvm/versions/node/v25.2.1/bin/node`, and those paths move on the
  next upgrade. The author lost four jobs this way, silently, for five weeks.
- **Sleep.** A laptop is asleep at the time you picked. `StartCalendarInterval` fires once on
  wake if it missed, but only for that one slot, and only per job.

So there is one signed runner that holds Full Disk Access, two LaunchAgents that start the
dispatcher through it, and a folder per tool. Every tool inherits the grant and the PATH.

## How it is wired

```
launchd
  fleet.automations           hourly at :30   -> Automations run-all.sh --scheduled
  fleet.automations-frequent  every minute    -> Automations run-all.sh --frequent
                                                   |
                                                   +-> Automations tools/<name>/<name>.sh
```

| piece | where | what |
| --- | --- | --- |
| runner | `~/Library/Application Support/automations/Automations` | a copy of `/bin/bash`, ad-hoc signed with its own identifier, granted Full Disk Access once |
| dispatcher | `~/fleet/automations/mac/run-all.sh` | finds due tools and runs each through the runner |
| tools | `~/fleet/automations/mac/tools/<name>/<name>.sh` | one folder per job, tracked in your fleet repo |
| cadence | `tools/<name>/cadence` | optional. `hourly`, or `every <N>m`. Absent means daily |
| logs | `tools/<name>/logs/<name>.log`, `dispatcher.log` | gitignored |
| state | `~/.local/state/automations/` | last daily pass, last run of each `every` tool |

The runner sits outside `~/Desktop` and `~/Documents` on purpose: launchd refuses to start a
binary stored in a protected folder. Its own code signing identifier gives it a separate entry
in Full Disk Access, so granting it does not grant your shell anything.

### Cadence

| `cadence` file | runs | lane |
| --- | --- | --- |
| absent | daily, on the first hourly fire at or after 23:30. A 23:30 missed while the Mac slept runs on wake | `--scheduled` |
| `hourly` | every hourly fire, at :30 | `--scheduled` |
| `every 5m` | once 5 minutes have passed since its last run, checked every minute | `--frequent` |

Two lanes so a long nightly pass never delays a frequent tool. Frequent tools must be quick and
quiet: the dispatcher logs only their failures and trims their logs past 1 MB. A specific clock
time other than these is a real limit of the design. Change `DAILY_AT` for everything, or say so;
don't invent a parallel scheduler.

## Install

Enable `mac-automations` on a Mac. `./install.sh` runs this package's `install.sh`, which:

1. builds the runner, once: `cp /bin/bash` then `codesign -s - -f --identifier fleet.automations.runner`
2. copies the reference [`run-all.sh`](run-all.sh) into `<fleet>/automations/mac/` with an empty
   `tools/`, unless you already have one
3. writes the two LaunchAgents from [`fleet.automations.plist`](fleet.automations.plist) and
   [`fleet.automations-frequent.plist`](fleet.automations-frequent.plist) (`__HOME__` and
   `__AUTOMATIONS__` filled in) and loads them
4. prints the one step only you can do:

> System Settings > Privacy & Security > Full Disk Access > **+** > Cmd+Shift+G > paste
> `~/Library/Application Support/automations/Automations` > turn it on.

Never rebuild the runner once granted. A modified binary keeps its entry in the list but loses
the grant. If reads that used to work start failing, toggle `Automations` off and on.

## Adding a tool

```bash
cd ~/fleet/automations/mac
mkdir -p tools/inbox-digest
$EDITOR tools/inbox-digest/inbox-digest.sh && chmod +x tools/inbox-digest/inbox-digest.sh
echo hourly > tools/inbox-digest/cadence      # optional
./run-all.sh inbox-digest                     # one run, now
```

Rules that keep it working:

- **Idempotent.** It runs on schedule whether or not the last run did anything.
- **Absolute paths for files; names for tools.** There is no useful cwd and no shell profile.
  Call `node`, `aws`, `uv` by name and let the dispatcher's PATH find them. A Python venv must
  sit on a uv-managed Python (`uv venv --managed-python`), not Xcode's or Homebrew's, which
  vanish on upgrade.
- **Exit non-zero on real failure**, so `dispatcher.log` records it.
- **Secrets in the environment or a gitignored file**, never in the script.
- **Never another LaunchAgent, and never special-case a tool in `run-all.sh`.** Schedule
  differences go in `cadence`. Tools you stop scheduling but want to keep go in `manual/`.
- Add a row to your automations registry (`templates/automations-README.md`) in the same commit.

## Testing: agent shells lie

Running a tool from an agent's shell proves nothing about permissions. macOS attributes access
to whatever launched the process, an agent shell has no grant, and it reports a false denial
(or a false success, if your terminal has its own grant). Test protected reads through launchd:

```bash
cat > ~/Library/LaunchAgents/fleet.automations-test.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>fleet.automations-test</string>
  <key>ProgramArguments</key><array>
    <string>$HOME/Library/Application Support/automations/Automations</string>
    <string>$HOME/fleet/automations/mac/run-all.sh</string>
    <string>inbox-digest</string>
  </array>
</dict></plist>
EOF
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/fleet.automations-test.plist
launchctl kickstart "gui/$(id -u)/fleet.automations-test"
sleep 5; tail ~/fleet/automations/mac/tools/inbox-digest/logs/inbox-digest.log
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/fleet.automations-test.plist
rm ~/Library/LaunchAgents/fleet.automations-test.plist
```

## Verify

```bash
launchctl list | grep fleet.automations      # both loaded
tail ~/fleet/automations/mac/dispatcher.log  # a "finished" line within the hour
```

## Health

No `check.sh`. Read `dispatcher.log` for `exit=` lines that are not 0, or wire a frequent tool
that alerts on them.

## A second, shared Mac

The same pattern works on a Mac you share but don't manage, such as a family or office machine
reached over Tailscale SSH, where your fleet repo is not checked out:

- One LaunchAgent at login (`RunAtLoad`) plus every 60 s, running `run-all.sh --scheduled`
  through that user's own signed runner. Their Full Disk Access, Accessibility or Screen
  Recording grants go to that runner once.
- A tool slows itself down with an `every` file holding seconds. A tool writes a log only when
  it prints something or fails.
- Keep the source in your fleet repo under that machine's folder and deploy it with
  `rsync`, since the box never pulls the repo.
- LaunchAgents only run while that user is logged in to the GUI. Keep-alive tools fit well here,
  such as keeping [sill](../sill/) or a remote desktop app running.

## Linux

Workers use one systemd timer per job instead. See [linux-automations](../linux-automations/).
Don't port either design to the other OS.
