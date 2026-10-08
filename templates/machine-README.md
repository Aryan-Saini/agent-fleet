# <name>

<One line: what this machine is for.>

| | |
| --- | --- |
| role | <controller / worker / remote> |
| OS | <name and version> |
| hardware | <cpu, ram, gpu, disks> |
| reach it | `ssh <name>` |
| drop folder | `~/drop` |
| packages | <from machine.env> |

## Storage

<Where big data goes, what must never be written to, what is scratch.>

## Scheduled jobs

Listed in [`automations/README.md`](../../automations/README.md). Do not keep a second list here.

## Installed versions

Updated by `/fleet-update` at the end of every run.

| tool | version | updated |
| --- | --- | --- |
| <tool> | <version> | <date> |

## Update log

Newest first. One line per run: date, what changed, anything deferred.

## Gotchas

<Things that cost real debugging time on this machine. Write the symptom first.>
