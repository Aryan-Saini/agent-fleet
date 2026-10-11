# accounts

Every tool in the fleet needs you signed in somewhere: Claude, Codex, Cursor, GitHub,
OpenRouter, T3, Convex, Linear, PostHog. This package is the list, the rule for how each one
reaches every machine, and a check that tells you which are missing.

## The rule: logins stay put, keys travel

| kind | examples | how it gets to a machine |
| --- | --- | --- |
| **login** (OAuth, refreshes itself) | Claude Code, Codex, Cursor, `gh`, T3 Connect, Convex CLI | you log in by hand **on each machine**. Never copy the token files |
| **key** (static string) | OpenRouter, Linear, PostHog, AWS, Google service account | written once on the controller, pushed with `fleet secrets push <machine>` |

Logins rotate their tokens. Copy one to a second machine and the first refresh logs the other
out (Codex's refresh tokens are single use, so it fails within hours). Keys don't rotate on
their own, so one source of truth plus a push is safe, and rotating one is one edit and one push.

Nothing here touches git. Keys live in `~/.config/agent-secrets.env` (mode 600, from
`templates/agent-secrets.env`) and files like a service account JSON live in
`~/.config/fleet/secrets/`. `fleet secrets push` sends both, plus postdraft's
`~/.postplan/config.json`, over ssh with mode 600.

## The accounts

The setup prompt asks which of these you use and walks only those.

| account | for | login or key | how |
| --- | --- | --- | --- |
| Claude | Claude Code | login, per machine | `claude`, then `/login`. A headless box prints a URL to open elsewhere |
| ChatGPT / Codex | Codex CLI, Codex Computer Use | login, per machine | `codex login`, `codex login --device-auth` on a headless box |
| Cursor | `cursor-agent` | login, per machine | `cursor-agent login` |
| GitHub | `gh`, git over ssh | login, per machine | `gh auth login`; each machine gets its own ssh key added to GitHub |
| T3 Code | phone access | login, per machine | see `packages/t3-remote` |
| OpenRouter | opencode, cheap models | key | `OPENROUTER_API_KEY` |
| Convex | postdraft's server, your apps | login per machine; deploy keys per project | `npx convex login`. A project's deploy key goes in that project's `.env.local`, not here |
| Linear | issues from agents | key | `LINEAR_API_KEY` |
| PostHog | analytics from agents | key | `POSTHOG_PERSONAL_API_KEY` |

Add rows for anything else you use. A tool with an MCP server reads its key from the
environment: see `packages/mcp` for getting keys into services and GUI apps too.

## Your own cloud, for the best experience

Optional, but several tools get better with it: postdraft can store files in your S3 bucket,
agents can back up their history, and Google APIs (Maps, Gemini, Drive) need a project.

- **AWS.** Your own account. Create an IAM user for agents with only the policies it needs (an
  S3 bucket of its own to start), make an access key, and put it in `agent-secrets.env`. Never
  give agents your root account or an admin user.
- **Google Cloud.** Your own project. Enable the APIs you want, create a service account with
  only those roles, download its JSON key to `~/.config/fleet/secrets/gcp-service-account.json`,
  and uncomment `GOOGLE_APPLICATION_CREDENTIALS`. A plain API key (Maps, Gemini) goes in
  `agent-secrets.env` instead.

Both then reach every machine with `fleet secrets push`.

## Let an agent fetch the keys

Copying keys out of dashboards is the slow part. On a Mac, an agent can do it with **Codex
Computer Use**: install the ChatGPT desktop app, sign in, turn on Computer Use, and grant it
Screen Recording and Accessibility in System Settings. Then the agent opens each key page, clicks
through to "create key", and writes the key straight into `agent-secrets.env` without printing
it in the chat. You still type every password and 2FA code. The `control-computer` skill is the
playbook, with [Peekaboo](../peekaboo/) as the vendor-neutral fallback.

## Verify

```bash
fleet secrets check         # every key: set or MISSING, values never shown
fleet health                # this package's check, plus agent-clis for the logins
```

## Health

`check.sh`: `agent-secrets.env` exists, is mode 600, and has no uncommented key left empty. No
heal: a key needs you. Logins are checked by `packages/agent-clis`.

## Updating

Rotate a key: edit `agent-secrets.env` on the controller, `fleet secrets push` every machine,
restart long-running services (the T3 backend), revoke the old key at the provider.
