---
name: remove-project
description: Retire a project. Pushes every branch and worktree so GitHub is current, makes a mandatory archive commit, unregisters it from T3 Code on every machine, strips everything regenerable, compresses it, and moves the archive to the worker's backup disk. Use when the user says "remove project", "archive this project", "retire X", "I'm done with X", or asks to clean a finished project off their machines.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin]
  scope: fleet
  requires: "gh, an ssh alias for the worker, and a writable archive directory on the worker (e.g. /mnt/backup/archive)"
---

# Retire a project

Destructive and mostly irreversible. Work strictly in this order. Nothing gets deleted until its
archive exists on the worker and has been verified.

**Nothing is left on the laptop.** The controller's tarball streams straight to the worker over
ssh, never written to local disk first.

## Where it lands

On the worker's bulk disk, split by which machine the copy came from:

```
<archive root>/
  controller/<parent folder>/<project>.tar.gz
  <worker>/<repo>.tar.gz
```

Write a sibling `<name>.txt` next to each: remote URL, archive date, and every branch with its SHA.
That manifest is what makes the tarball restorable a year later. Keep the archive root out of any
snapshot rotation, or old snapshots will hold the same bytes twice.

## 1. Get GitHub current

Nothing is destroyed here, so do all of it first.

- Push every local branch in the main checkout, setting upstream where it is missing.
- The same in **every worktree**: `git worktree list`, plus `~/.t3/worktrees/<project>/*`.
- The same on each worker's `~/dev/<repo>`, which can carry its own local branches.
- Verify every local branch has a remote ref at the same SHA. If not, stop.

## 2. The archive commit, always

Every retirement makes a commit, no exceptions, even when the tree is spotless. It marks when and
why the project stopped.

```bash
git commit --allow-empty -m "archive commit $(date +%Y-%m-%d)"
git push
```

`--allow-empty` is the point. If there **are** uncommitted changes, show them to the user first
and let them decide what goes in. Never silently sweep a dirty tree into it.

## 3. Unregister from T3 Code

Through each machine's MCP (`t3-code` locally, `t3-<worker>` remotely): find the id with
`t3_project_list`, then `t3_project_delete`. If it refuses because the project still has threads,
ask before passing `force: true`, which deletes those threads.

Without the MCP:

```bash
pnpm dlx t3@<installed app version> project remove <path>
ssh <worker> 't3 project remove ~/dev/<repo>'
```

Then `git worktree remove` each worktree and delete `~/.t3/worktrees/<project>/`. After step 1,
so nothing unpushed goes with them.

## 4. Strip everything regenerable

```bash
<this skill>/strip-regenerables.sh <project>            # dry run first
<this skill>/strip-regenerables.sh <project> --apply
```

Read the dry run's "keeping" list to the user before applying. The script defines regenerable as
"git ignores it", which sweeps `node_modules`, `.next`, `.expo`, `ios/Pods`, `.venv`, `dist` and
every future equivalent with no list to maintain.

`.env` files, signing keys, `.p8`/`.pem` certs and local databases are gitignored too and are
**not** regenerable. The script finds them first, refuses to remove a directory holding one
(deleting around it instead), and re-verifies they survived. Don't work around it, and don't
substitute `git clean -Xfd`: under `-X` the `-e` flag *adds* ignore rules rather than sparing
files, which is the opposite of protection.

Run it on the worker's copy too.

## 5. Compress

Controller side, streamed so no archive touches local disk:

```bash
ssh <worker> "mkdir -p <archive root>/controller/<parent>"
tar -czf - -C <parent dir> <project> | ssh <worker> "cat > <archive root>/controller/<parent>/<project>.tar.gz"
```

Worker side:

```bash
ssh <worker> "mkdir -p <archive root>/<worker> && tar -czf <archive root>/<worker>/<repo>.tar.gz -C ~/dev <repo>"
```

## 6. Verify, then delete

Never the reverse.

```bash
ssh <worker> "tar -tzf <archive> | head; ls -la <archive>"
```

Only once both archives list correctly and the sizes look sane, print exactly what is about to be
deleted and get the user's confirmation, then:

```bash
rm -rf <controller path>
ssh <worker> "rm -rf ~/dev/<repo>"
```

## Left alone

The GitHub repo. Retiring locally does not archive or delete it on GitHub.

## Report

Both archive paths with sizes, the archive commit SHA, every T3 registration removed, and
confirmation that nothing remains on the laptop.
