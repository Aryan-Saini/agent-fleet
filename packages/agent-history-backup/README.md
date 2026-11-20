# agent-history-backup

Every agent conversation on every machine, kept forever in one encrypted
[restic](https://restic.net) repository in S3. One snapshot per machine per day.

Why it matters: Claude Code deletes transcripts in `~/.claude/projects` on a rolling 30-day
window. Codex, Cursor, opencode and T3 Code keep everything, but on exactly one disk. A month
from now you will want the session where an agent figured out that one migration. Without a
backup it is gone.

## What gets backed up

| harness | paths | how |
| --- | --- | --- |
| Claude Code | `~/.claude/projects`, `~/.claude/history.jsonl` | files |
| Codex | `~/.codex/sessions`, `archived_sessions`, `history.jsonl`; `state_*.sqlite`, `thread_history_*.sqlite` | files; the two dbs via `.backup`. Without the index dbs, restored transcripts can't be listed |
| Cursor | `~/.cursor/projects`, `chats` (CLI agent); the IDE's `state.vscdb`, `conversation-search.db`, `workspaceStorage` | the multi-GB `state.vscdb` is reduced to its conversation keys, re-extracted only when it changes |
| opencode | `~/.local/share/opencode/opencode.db` | `.backup` |
| T3 Code | `~/.t3/userdata/statev2.sqlite` (every thread), `~/.t3/userdata/attachments` | `.backup` plus `REINDEX`; never the rest of `userdata/`, which holds `secrets/` |
| macOS apps | Antigravity, Wispr Flow, if present | `.backup` |

**Live sqlite needs `.backup`.** A plain copy of a database with a hot WAL is not consistent. The
script copies each store with `sqlite3 <db> ".backup '<copy>'"`, runs `pragma quick_check` on the
copy, and backs up the copy. `-wal` and `-shm` sidecars are excluded, because a sidecar restored
without its parent db can look valid and read wrong. T3's store needs a `REINDEX` on the copy
first: its indexes drift in normal use and fail the check even on a faithful copy.

**Check that new stores are in it.** Harnesses rename their databases (T3's went from
`state.sqlite` to `statev2.sqlite`), and the author once found his T3 history missing from the
snapshots. After any harness update, `agent-history-restore ls statev2` should list today.

## The repository

| | |
| --- | --- |
| repo | `s3:s3.<region>.amazonaws.com/<your-bucket>/restic`, one repo for every machine |
| snapshots | `--host <machine> --tag daily`, `--compression max` |
| retention | **forever**. Never run `restic forget` or `prune`. Dedup means an unchanged file costs nothing in a new snapshot |
| password | `~/.config/restic/agent-history.pass`, mode 600, the same on every machine. Keep a second copy off the machine (password manager or cloud secret store). Lose it and the repo is unreadable |
| config | `~/.config/restic/agent-history.env`: `RESTIC_REPOSITORY`, optional `AWS_PROFILE`, optional `BACKUP_HOST`. Names, not secrets |

### Bucket settings

| setting | value | why |
| --- | --- | --- |
| Block Public Access | all four on | nothing here is ever public |
| default encryption | SSE-S3 (AES256) | on top of restic's own encryption |
| versioning | on | an overwritten or deleted object can be recovered |
| lifecycle | noncurrent versions expire after 90 days; current objects to Standard-IA after 60 days | restic deletes only its lock files, so old versions are mostly noise; IA halves the cost of data you rarely read |
| access | an IAM user or profile allowed `s3:ListBucket` on the bucket and `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on `<your-bucket>/restic/*`, nothing else | restic needs delete for its locks |

Create it once:

```bash
aws s3api create-bucket --bucket <your-bucket> --region <region> \
  --create-bucket-configuration LocationConstraint=<region>   # omit this line for us-east-1
aws s3api put-public-access-block --bucket <your-bucket> --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket <your-bucket> --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-versioning --bucket <your-bucket> --versioning-configuration Status=Enabled
aws s3api put-bucket-lifecycle-configuration --bucket <your-bucket> --lifecycle-configuration '{
  "Rules":[{"ID":"tidy","Status":"Enabled","Filter":{},
    "NoncurrentVersionExpiration":{"NoncurrentDays":90},
    "Transitions":[{"Days":60,"StorageClass":"STANDARD_IA"}]}]}'
openssl rand -base64 32 > ~/.config/restic/agent-history.pass && chmod 600 ~/.config/restic/agent-history.pass
restic init     # with RESTIC_REPOSITORY and the password file set
```

The same bucket can hold other archives under their own prefixes, such as the hub's request logs
from [cliproxy](../cliproxy/).

## Install

1. Install `restic`, `sqlite3` and the AWS CLI credentials restic will use, on each machine.
2. Copy the password file and `agent-history.env` to each machine, mode 600 (`fleet secrets push`
   carries files in `~/.config/fleet/secrets/`; or scp them).
3. Schedule [`agent-history-backup`](agent-history-backup), the same script on both OSes:
   - **macOS:** a [mac-automations](../mac-automations/) tool, so it inherits Full Disk Access
     (Cursor's and other apps' stores live under protected `~/Library` paths):
     `mkdir -p ~/fleet/automations/mac/tools/agent-history-backup` and a two-line
     `agent-history-backup.sh` that `exec`s the script. Daily is the default cadence.
   - **Linux:** copy the script to `~/.local/bin` and [`units/`](units/) to
     `~/.config/systemd/user/`, then `systemctl --user enable --now agent-history-backup.timer`.
     `Persistent=true`, so a day the worker was down still gets its snapshot.
4. `agent-history-restore` lands on PATH from this package's `bin/`.

## Verify

```bash
agent-history-backup                         # one run by hand (on macOS, also test via launchd)
agent-history-restore ls                     # snapshots: one per host per day
agent-history-restore ls <session-id>        # where a transcript appears
```

## Restore

```bash
agent-history-restore ls 3f2a9c              # find it, note the snapshot id and full path
agent-history-restore get <snapshot> <path> /tmp/restore
```

Files land under `/tmp/restore/<full path>`. Copy them into place yourself, with the harness
closed. Restore a whole `.sqlite` rather than mixing it with a live WAL.

## Health

The script exits non-zero and calls `fleet alert` on any failure. Every few weeks, restore one
old transcript for real; an untested backup is a hope.
