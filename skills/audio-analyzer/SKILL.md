---
name: audio-analyzer
description: Transcribe any audio or video file on this computer into a markdown or text note saved anywhere. Use when the user gives an audio/video file path (mp3, m4a, wav, mov, mp4, etc.) or asks to transcribe a recording, voice memo, meeting, lecture, podcast, or video clip. Three backends, free local faster-whisper (offline), paid OpenAI gpt-4o-transcribe, or Google Gemini. ALWAYS ask the user which backend and where to save before running.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "python3, ffmpeg/ffprobe, plus one backend: pip faster-whisper (local), OPENAI_API_KEY, or GEMINI_API_KEY"
---

# Audio analyzer

Transcribe any audio or video file to a markdown (or txt) note.

Script: `transcribe.py` in this folder. The commands below assume the skill is linked at
`~/.agents/skills/audio-analyzer`; use whichever path your harness links it to.

## Ask first

Before running, ask two things unless the user already said them:

1. **Backend.**
   - `local`: free, offline, faster-whisper `large-v3`. No key, no cost. The default and the recommendation.
   - `openai`: paid, gpt-4o-transcribe, about $0.006/min, needs `OPENAI_API_KEY`.
   - `google`: gemini-2.5-flash, needs `GEMINI_API_KEY` (falls back to `GEMINI_API_KEY_FALLBACK`, then `GOOGLE_API_KEY`).
2. **Output location.** Default is next to the source file. Any folder works via `--out <dir>`.

Use your harness's ask-the-user tool for the backend. If the user already said ("use local",
"the free one", "transcribe to ~/Notes"), skip that question.

## Run

```bash
S=~/.agents/skills/audio-analyzer/transcribe.py

python3 $S "/path/to/file.mp3"                        # local, note next to the source
python3 $S --backend openai "/path/to/file.mov"       # paid OpenAI
python3 $S --backend google "/path/to/file.mp4"       # Gemini
python3 $S --out ~/Notes "/path/file.m4a"             # notes into a chosen folder
python3 $S --txt "/path/file.wav"                     # plain .txt instead of markdown
python3 $S file1.mp3 file2.mov                        # several files
```

| Flag | Effect |
| --- | --- |
| `--backend local\|openai\|google` | engine. Default `local`; env `TRANSCRIBE_BACKEND` changes the default |
| `--out <dir>` | output folder, created if missing. Default: the source file's folder |
| `--txt` | write `.txt` instead of `.md`, no frontmatter |
| env `WHISPER_MODEL` | local model size: `large-v3` (default), `medium`, `small`, `base`. Smaller is faster and worse |

## Output

- Markdown (default): YAML frontmatter (date, source, duration, tags), then `## Transcript`.
- `--txt`: the raw transcript only.
- Filename is the source stem: `recording.mp3` becomes `recording.md`.

## Keys

The script reads keys from the environment, or from a `.env` next to the script
(`OPENAI_API_KEY=`, `GEMINI_API_KEY=`). That `.env` must stay out of git: the repo's
`.gitignore` covers it, and it should be mode 600. Prefer your machine's shared secrets file if
you have one and export the variables from there.

## How it works and what to know

- ffmpeg extracts a mono 16 kHz mp3 first, so video files work the same as audio.
- Supported: `mp3 m4a wav flac aac ogg opus wma`, and video `mov mp4 mkv avi webm m4v flv`.
- Local handles long files in one pass, no chunking. The first run downloads the model
  (about 3 GB for `large-v3`). On a laptop without a GPU, `medium` is a fair trade.
- OpenAI caps uploads near 25 MB and Gemini inline requests near 20 MB, so the script splits
  longer audio into 10 minute chunks and joins the text.
- The Gemini backend tries the next key only on quota or auth errors, so a bad file fails fast.
- Deps: `pip install faster-whisper` (local), `openai` (openai), `google-genai` (google).
  Missing ones exit with the exact install command.
- On a headless worker, `local` is the cheap choice for long recordings: run it there and copy
  the note back.
