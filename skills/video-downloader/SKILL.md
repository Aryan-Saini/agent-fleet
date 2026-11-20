---
name: video-downloader
description: Download videos or audio from YouTube and other sites (playlists, talks, podcasts, clips) for offline viewing, editing, transcription or archival. Use when the user pastes a video URL and says download, save, grab, rip the audio, get it as mp3, or wants a whole playlist or channel saved. Handles quality, format and audio-only choices.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "yt-dlp and ffmpeg on PATH (brew install yt-dlp ffmpeg, or pacman -S yt-dlp ffmpeg)"
---

# Video downloader

A thin layer over [yt-dlp](https://github.com/yt-dlp/yt-dlp). It supports YouTube and about a
thousand other sites. The original idea came from a community skill in
[ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills); this
version is rewritten around plain yt-dlp commands.

## Before you run

Ask only what the user didn't already say:

1. **Video or audio only?** Podcasts, lectures and music usually want audio.
2. **Quality.** Default is best available up to 1080p. 4K files are large; say the size first.
3. **Where.** Default `~/Downloads`. Never write into a repo unless asked.

Only download things the user has the right to keep: their own uploads, freely licensed
material, or personal offline viewing where the site's terms allow it.

## Commands

```bash
OUT=~/Downloads
T="%(title)s [%(id)s].%(ext)s"

# best video up to 1080p, merged to mp4
yt-dlp -f "bv*[height<=1080]+ba/b[height<=1080]" --merge-output-format mp4 -o "$OUT/$T" "<url>"

# audio only, mp3 (use m4a or opus to skip the re-encode)
yt-dlp -x --audio-format mp3 --audio-quality 0 -o "$OUT/$T" "<url>"

# keep metadata: thumbnail, description, embedded chapters and subtitles
yt-dlp --embed-thumbnail --embed-metadata --embed-chapters \
  --write-subs --write-auto-subs --sub-langs "en.*" --embed-subs -o "$OUT/$T" "<url>"

# a whole playlist, numbered, into its own folder
yt-dlp -o "$OUT/%(playlist_title)s/%(playlist_index)03d %(title)s.%(ext)s" "<playlist-url>"

# a clip only (needs ffmpeg)
yt-dlp --download-sections "*00:01:30-00:03:00" -o "$OUT/$T" "<url>"

# look before you download: formats and sizes, or just the title and duration
yt-dlp -F "<url>"
yt-dlp --print "%(title)s | %(duration_string)s | %(filesize_approx)s" "<url>"
```

For batches, put one URL per line in a file and use `-a urls.txt`. Add
`--download-archive ~/Downloads/.yt-dlp-archive` so a rerun skips what already finished.

## Report back

The absolute path of every file written, its duration and size. If the user wants a transcript
next, hand the file to the `audio-analyzer` skill.

## Gotchas

- **"Sign in to confirm you're not a bot" or HTTP 403.** Update first (`yt-dlp -U`, or
  `brew upgrade yt-dlp`). Sites change often and an old yt-dlp is the usual cause.
- **Age-gated or members-only video.** `--cookies-from-browser chrome` (or `firefox`, `safari`)
  reuses the user's own browser login. Ask before you do it. Never copy a cookie file anywhere.
- **Separate video and audio files left behind.** ffmpeg was missing when yt-dlp tried to merge
  them. Install it and rerun.
- **Filenames with odd characters.** Add `--restrict-filenames` when the file feeds a script.
- **Headless worker.** Downloading on a worker is fine. Move the file to the user's machine
  with your usual file-sharing path (a synced drop folder, `scp`) and say where it landed.
