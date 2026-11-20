---
name: messages
description: The user's iMessage and SMS history, read from the controller Mac. Use when the user asks what someone texted, to find or summarize a conversation, check unread texts, look up what was said in a group chat, or says "text X", "send a message to", "reply to <name>". Read-only unless the user explicitly says to send.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "a Mac with Messages signed in and Full Disk Access for whatever runs the script; off the Mac, an ssh alias to it ($MSGS_HOST, default `controller`)"
---

# Messages

`scripts/msgs` reads the Mac's Messages database, `~/Library/Messages/chat.db`, opened
read-only. Stdlib Python, 3.9 compatible, so macOS's system `python3` runs it. On any other
machine it pipes itself to the Mac over `ssh $MSGS_HOST` and runs there, so the commands are the
same everywhere. The Mac must be awake: there is no cloud API for iMessage.

```bash
scripts/msgs recent                              # latest 20 threads with unread counts
scripts/msgs thread "<name>"                     # last 40 messages with that person
scripts/msgs thread '#<id>' --since 2026-09-01   # a chat by the id that recent/thread print
scripts/msgs search "<text>" --who "<name>"      # search, optionally inside one chat
scripts/msgs send "<name>" "On my way"           # dry run: shows recipient and text
scripts/msgs send "<name>" --file ~/doc.pdf "here it is"   # files (repeatable) and optional text
```

`<who>` matches contact names (from the Mac's local address books), phone numbers in any
format, emails and group names. An exact name beats partial ones, and one person's several 1:1
chats (phone, email, SMS) merge into one thread. When it is still ambiguous, the script lists
`#<id>` choices; pass one back. Your own messages are labelled `me` (`MSGS_ME` changes it).

## Permissions (the part that takes an afternoon)

chat.db and the AddressBook databases sit behind macOS privacy protection (TCC). A process that
lacks **Full Disk Access** gets `unable to open database file` or `authorization denied`, even as
the file's owner. TCC grants go to the *responsible app*: whatever launched the process.

| How the script runs | What needs Full Disk Access |
| --- | --- |
| a terminal on the Mac | the terminal app (Terminal, iTerm, ...) |
| an agent app on the Mac (T3 Code, Cursor, Claude desktop) | that app |
| from the worker, over `ssh <controller>` | sshd. Turn on System Settings > General > Sharing > Remote Login > (i) > **Allow full disk access for remote users**. On older macOS, add `/usr/libexec/sshd-keygen-wrapper` to the Full Disk Access list instead |
| a LaunchAgent or automation runner | the runner binary itself. A common pattern: a private copy of `bash` in its own app folder, granted Full Disk Access, that runs every scheduled job |

Sending also needs an **Automation** grant: the responsible app may control Messages.app. macOS
asks once, on the first send. Over ssh there is no screen to click "Allow", so trigger that first
send from a session on the Mac, or approve it in System Settings > Privacy & Security >
Automation.

## Sending

**Read-only by default. Send only when the user explicitly says to send.** A request to draft,
reply or "text X" means: show the `send` dry run and wait. Add `--confirm` only after the user
says send.

- Sending goes through Messages.app with AppleScript, into an **existing** chat addressed by the
  chat's `guid` from chat.db (`any;-;+1...`), which AppleScript's `chat id` accepts. Starting a
  new conversation with someone never messaged before is not supported.
- **Files: always `--file`, never hand-written osascript.** A local path works from any machine:
  off the Mac it is copied over first. The script stages each file in `~/Pictures/msgs-outbox`
  and sends it as an `alias`. A plain `send POSIX file` delivers an empty bubble and no file.
  Messages also reads from `~/Pictures` more reliably than from elsewhere. The staged copy is
  deleted afterwards; Messages keeps its own.
- After `--confirm` the script polls chat.db for up to 30 s and prints `sent and confirmed` only
  when every file (by name) and the text are in the chat with no error. Otherwise it exits
  non-zero and says what is missing, including any empty bubble.
- On a failure, never just resend. Read `msgs thread` first, then tell the user exactly what went
  out so they can unsend strays.

## Reading the database: gotchas

- **Text is usually not in `text`.** Modern macOS leaves `message.text` NULL and stores the body
  in `attributedBody`, an `NSAttributedString` in Apple's typedstream format. `body()` finds the
  `NSString` marker and reads the length-prefixed UTF-8 after it (one byte, or `0x81` then 2
  bytes, or `0x82` then 4 bytes). Skip this and most messages read as empty.
- **Dates** are nanoseconds since 2001-01-01 UTC (seconds on very old rows).
- **Tapbacks** are rows with `associated_message_type != 0`. The script skips them.
- **Attachments** show as `[attachment]` plus any caption. `U+FFFC` placeholders are stripped.
- **1:1 vs group**: `chat.style` is 45 for a 1:1 chat. Groups have a `display_name` when named,
  otherwise the title is the member list.
- **Contacts** come from `~/Library/Application Support/AddressBook/**/AddressBook-v22.abcddb`,
  matched on email or the last 10 digits of a phone number.
- Open SQLite with `file:...?mode=ro` so a reader can never lock or write Messages' live database.

## Privacy

Message content is the most personal data on the machine. Quote only what the question needs,
summarize instead of dumping threads, and never paste messages into a public place (a PR, an
issue, a shared doc) or send them to an outside service.
