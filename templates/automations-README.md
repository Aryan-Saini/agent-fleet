# Automations

Every scheduled job on every machine: what it does, why it exists, when it fires, where it
lives. Adding or retiring a job updates this file in the same commit. Use the `automation`
skill to add one.

| machine | job | when | why it exists | script | logs |
| --- | --- | --- | --- | --- | --- |
| <worker> | `fleet-health` | every 15 min, after boot | heals what is safe, alerts on the rest | `bin/fleet-health` | `~/.local/state/fleet/logs/health.log` |
| <worker> | `fleet-sync` | every 30 min, `Persistent=true` | receives rules and skills from the controller | `bin/fleet-sync` | `~/.local/state/fleet/logs/sync.log` |
| <worker> | `fleet-resume` | at boot, only with an open work order | finishes and reports risky work after a reboot | `bin/fleet-workorder` | `~/.local/state/fleet/logs/workorder-*.log` |

Scripts and unit files are tracked here, because the repo copy is what survives a rebuild.
Logs never are.

## Retired

| machine | job | removed | why |
| --- | --- | --- | --- |
