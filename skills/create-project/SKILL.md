---
name: create-project
description: Set up a project's T3 Code environment. Make the folder a private GitHub repo under the right owner, register it as a T3 Code project on the controller and every worker with a pinned default model, and give it an icon (T3 project icon and Finder folder icon). Stack agnostic; it does not scaffold code, and it takes an existing repo as happily as a bare folder. Use whenever the user says "create a project", "set this up in t3", "register this on the worker too", "add this repo to t3", "make me a repo for X", or hands over a GitHub URL or a checkout and wants the T3 side done.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin]
  scope: fleet
  requires: "gh logged in, pnpm, an ssh alias for each worker, T3 Code MCP access to each machine (t3-code locally, t3-<worker> remotely), python3 with Pillow and the Xcode command line tools for the folder icon"
---

# Set up a project's T3 environment

Repo, then T3 Code on every machine, then icon. **This skill does not scaffold code.** If the
folder needs an app in it, that is a separate job; here the project is an input, whatever is or
isn't inside it.

## Three ways in

Work out which one you're looking at before asking anything.

| what you got | do |
| --- | --- |
| **an existing repo**, a folder with a git remote | skip step 1. `git remote get-url origin` already answers the owner |
| **a GitHub URL**, not cloned yet | clone it under the right parent folder, then skip step 1. Ask which parent if it isn't obvious |
| **a bare folder**, or just a name | step 1 in full |

The first case is the common one: the user already has the repo and wants the T3 side. That path
asks nothing except the icon.

## Ask first

Only what the entry point leaves open, in one round of questions.

| question | when | options |
| --- | --- | --- |
| GitHub owner | only when creating the repo | personal (`<your-github-user>`) or an organization; if org, which (`<org-a>`, `<org-b>`) |
| icon | always, unless the repo already has a `t3.json` | generate one, the user supplies a path, or skip |
| folder | when not given | your parent folders, e.g. `~/Desktop/<personal>`, `~/Desktop/<company>` |

The folder and the owner are separate answers. Don't infer one from the other.

## 1. Repo, only if there isn't one

`git init` and an initial commit if it isn't a repo yet, then:

```bash
cd <project> && gh repo create <owner>/<name> --private --source=. --remote=origin --push
```

Wrong owner later: `gh api -X POST repos/<old>/<name>/transfer -f new_owner=<new>`, then fix
`git remote set-url` on **every** machine.

## 2. Register in T3 Code on every machine

Pin your default model on every project so a new thread never starts on whatever the global
default drifted to. Same MCP call per machine, no restart:

```text
t3_project_create  workspaceRoot=<root>  title=<title>
  defaultModelSelection={"instanceId":"claudeAgent","model":"<model id>","options":[{"id":"effort","value":"high"},{"id":"contextWindow","value":"1m"}]}
  scripts=[{"id":"worktree-setup","name":"Worktree setup","command":"\"$HOME/fleet/bin/t3-worktree-setup\"","icon":"configure","runOnWorktreeCreate":true}]
```

The `scripts` entry is worth having on any repo with a lockfile. Write `t3-worktree-setup` once:
T3 sets `T3CODE_PROJECT_ROOT` and `T3CODE_WORKTREE_PATH`; the script copies the main checkout's
gitignored `.env*` files into the new worktree (never overwriting) and installs dependencies, so
every thread or subagent that starts in a worktree can run the app at once. Set PATH inside it:
T3 may run with a GUI or systemd PATH that lacks your node toolchain.

| machine | `workspaceRoot` | `title` |
| --- | --- | --- |
| controller | the project folder | `<Name>` |
| each worker | `~/dev/<repo>` (absolute path) | `<Name> (<worker>)` |

Clone onto the worker over ssh, in the background for big repos:
`ssh <worker> 'git clone <ssh-url> ~/dev/<repo>'`. Don't use the remote MCP's
`t3_project_clone` for a real repo: the call gives up after about 60 s and reports a timeout
while the clone keeps going. Already there: `ssh <worker> 'git -C ~/dev/<repo> pull'`.

Already registered: `t3_project_update` with the id from `t3_project_list`. Its `scripts`
replaces the whole list, so pass the existing ones too.

Without the MCP, the CLI works but has no model flag, so the project rides the global default
(say so in the report):

```bash
pnpm dlx t3@<installed app version> project add <project> --title "<Name>"
ssh <worker> 't3 project add ~/dev/<repo> --title "<Name> (<worker>)"'
```

**Never write T3's sqlite directly.** It is an event store; a script that wrote to it once
corrupted project state for the author.

## 3. Icon

Generate one with whatever image tool you have, or take the user's file. A prompt that works: the
subject, then `flat vector app icon, square, transparent background, minimal, high contrast, crisp
geometric edges, no text, no drop shadows`. Generators pick their own size, so crop and resize
afterwards. Show it before wiring it in.

**T3 Code project icon**: a checked-in `t3.json` at the repo root covers every machine at once:

```json
{ "$schema": "https://t3.codes/schema/t3.json", "iconPath": "<path/to/icon.png>" }
```

`iconPath` is repo-relative and may point at any PNG already in the repo. Reuse the app's own icon
when there is one (an Expo app's `assets/images/icon.png`). Otherwise drop the PNG at the root as
`.t3-icon.png`. Without `t3.json`, T3 falls back to a detected favicon.

**Finder folder icon** (macOS):

```bash
<this skill>/set-folder-icon.sh <source.png> <project>
```

Add `.icon.icns` and `Icon?` to `.gitignore`. If Finder still shows a plain folder, that is the
icon cache, not a failure: check `GetFileInfo <folder>` for the `C` attribute.

Commit the icon work, push, and `git pull` on each worker so every copy matches.

## Report

Folder path, repo URL, every T3 project title, and which have the model pinned versus riding the
global default.
