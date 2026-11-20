#!/usr/bin/env python3
"""
Transcribe any audio/video file to a markdown note. Output goes anywhere.

Usage:
    python3 transcribe.py <file> [<file> ...]
    python3 transcribe.py --out <dir> <file> ...      # write notes into <dir>
    python3 transcribe.py --txt <file> ...            # plain .txt instead of .md
    python3 transcribe.py --backend openai <file>     # paid gpt-4o-transcribe
    python3 transcribe.py --backend local <file>      # free faster-whisper (default)

Output:
    Default: a markdown note next to each source file (same folder, .md).
    --out <dir>: all notes written into <dir> (created if missing).

Backends:
    local   faster-whisper, offline, free            (default)
    openai  gpt-4o-transcribe, needs OPENAI_API_KEY, ~$0.006/min
    google  gemini-2.5-flash, needs GEMINI_API_KEY (or GOOGLE_API_KEY)
  Env override: TRANSCRIBE_BACKEND=openai|google
Local model size via env WHISPER_MODEL (default large-v3; base/small/medium=faster/worse).

Deps: ffmpeg + ffprobe on PATH; pip install faster-whisper (local) or openai (openai).
"""
import os
import sys
import subprocess
import tempfile
import datetime
from pathlib import Path

MODEL = "gpt-4o-transcribe"
GEMINI_MODEL = "gemini-2.5-flash"
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "large-v3")
MAX_BYTES = 24 * 1024 * 1024  # OpenAI ~25MB cap; chunk under it
GEMINI_MAX_BYTES = 18 * 1024 * 1024  # Gemini inline-request cap (~20MB); chunk under it
AUDIO_EXTS = {".mp3", ".m4a", ".wav", ".flac", ".aac", ".ogg", ".opus", ".wma"}
VIDEO_EXTS = {".mov", ".mp4", ".mkv", ".avi", ".webm", ".m4v", ".flv"}

# load a .env sitting next to this script (optional, for OPENAI_API_KEY)
ENV_FILE = Path(__file__).parent / ".env"
if ENV_FILE.exists():
    for line in ENV_FILE.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

_openai_client = None
_whisper_model = None
_genai_clients = None


def get_genai_clients():
    """Return a list of genai clients, one per available key (primary + fallback)."""
    global _genai_clients
    if _genai_clients is None:
        try:
            from google import genai
        except ImportError:
            sys.exit("Missing google-genai. Run: pip install google-genai")
        keys = [os.environ.get(n) for n in
                ("GEMINI_API_KEY", "GEMINI_API_KEY_FALLBACK", "GOOGLE_API_KEY")]
        keys = [k for k in keys if k]
        if not keys:
            sys.exit("GEMINI_API_KEY not set. Add to .env next to this script or export it.")
        _genai_clients = [genai.Client(api_key=k) for k in keys]
    return _genai_clients


def get_openai_client():
    global _openai_client
    if _openai_client is None:
        try:
            from openai import OpenAI
        except ImportError:
            sys.exit("Missing openai. Run: pip install openai")
        if not os.environ.get("OPENAI_API_KEY"):
            sys.exit("OPENAI_API_KEY not set. Add to .env next to this script or export it.")
        _openai_client = OpenAI()
    return _openai_client


def get_whisper_model():
    global _whisper_model
    if _whisper_model is None:
        try:
            from faster_whisper import WhisperModel
        except ImportError:
            sys.exit("Missing faster-whisper. Run: pip install faster-whisper")
        print(f"  loading whisper model '{WHISPER_MODEL}' (first run downloads it)...")
        _whisper_model = WhisperModel(WHISPER_MODEL, device="auto", compute_type="int8")
    return _whisper_model


def ffprobe_duration(path: Path) -> float:
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(path)
    ])
    return float(out.strip())


def extract_audio(src: Path, out_mp3: Path):
    subprocess.run([
        "ffmpeg", "-y", "-i", str(src),
        "-vn", "-ac", "1", "-ar", "16000",
        "-b:a", "64k", str(out_mp3)
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def chunk_audio(mp3: Path, chunk_dir: Path, chunk_secs: int = 600) -> list:
    chunk_dir.mkdir(parents=True, exist_ok=True)
    pattern = str(chunk_dir / "chunk_%03d.mp3")
    subprocess.run([
        "ffmpeg", "-y", "-i", str(mp3),
        "-f", "segment", "-segment_time", str(chunk_secs),
        "-c", "copy", pattern
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return sorted(chunk_dir.glob("chunk_*.mp3"))


def transcribe_file_openai(audio: Path) -> str:
    client = get_openai_client()
    with open(audio, "rb") as f:
        resp = client.audio.transcriptions.create(
            model=MODEL, file=f, response_format="text",
        )
    return resp if isinstance(resp, str) else getattr(resp, "text", str(resp))


GEMINI_PROMPT = (
    "Transcribe this audio verbatim into clean, readable text. "
    "Return only the transcript with no commentary, headings, or timestamps."
)


def transcribe_file_google(audio: Path) -> str:
    from google.genai import types
    data = audio.read_bytes()
    last_err = None
    for client in get_genai_clients():
        try:
            resp = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=[GEMINI_PROMPT,
                          types.Part.from_bytes(data=data, mime_type="audio/mp3")],
            )
            return (resp.text or "").strip()
        except Exception as e:
            msg = str(e)
            last_err = e
            # try the next key only on quota/auth issues
            if not any(s in msg for s in ("quota", "RESOURCE_EXHAUSTED", "API key", "PERMISSION")):
                raise
    raise last_err


def transcribe_file_local(audio: Path) -> str:
    model = get_whisper_model()
    segments, _ = model.transcribe(str(audio), vad_filter=True)
    return " ".join(s.text.strip() for s in segments).strip()


def transcribe_media(src: Path, backend: str) -> tuple:
    duration = ffprobe_duration(src)
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        mp3 = td / "audio.mp3"
        print("  extracting audio...")
        extract_audio(src, mp3)
        size = mp3.stat().st_size
        # local whisper handles long audio natively - no chunking needed
        if backend == "local":
            print(f"  transcribing locally ({size/1e6:.1f}MB)...")
            return transcribe_file_local(mp3), duration
        transcribe_chunk = transcribe_file_google if backend == "google" else transcribe_file_openai
        cap = GEMINI_MAX_BYTES if backend == "google" else MAX_BYTES
        if size <= cap:
            print(f"  transcribing ({size/1e6:.1f}MB)...")
            return transcribe_chunk(mp3), duration
        print(f"  chunking ({size/1e6:.1f}MB)...")
        chunks = chunk_audio(mp3, td / "chunks")
        parts = []
        for i, c in enumerate(chunks, 1):
            print(f"  transcribing chunk {i}/{len(chunks)}...")
            parts.append(transcribe_chunk(c))
        return "\n\n".join(parts), duration


def write_note(src: Path, text: str, duration: float, out_dir: Path, as_txt: bool):
    out_dir.mkdir(parents=True, exist_ok=True)
    mtime = datetime.datetime.fromtimestamp(src.stat().st_mtime)
    date_str = mtime.strftime("%Y-%m-%d")
    mins, secs = int(duration // 60), int(duration % 60)
    if as_txt:
        out = out_dir / f"{src.stem}.txt"
        out.write_text(text.strip() + "\n")
    else:
        out = out_dir / f"{src.stem}.md"
        fm = (
            f"---\n"
            f"date: {date_str}\n"
            f"source: \"{src}\"\n"
            f"duration: \"{mins}m{secs:02d}s\"\n"
            f"tags: [transcript]\n"
            f"---\n\n"
            f"# {src.stem}\n\n"
            f"**Recorded:** {date_str}  \n"
            f"**Length:** {mins}m {secs:02d}s  \n"
            f"**File:** `{src}`\n\n"
            f"## Transcript\n\n"
        )
        out.write_text(fm + text.strip() + "\n")
    print(f"  -> {out}")
    return out


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)

    backend = os.environ.get("TRANSCRIBE_BACKEND", "local")
    out_dir = None
    as_txt = False

    if "--backend" in args:
        i = args.index("--backend")
        try:
            backend = args[i + 1]
        except IndexError:
            sys.exit("--backend needs a value: local | openai | google")
        del args[i:i + 2]
    if "--out" in args:
        i = args.index("--out")
        try:
            out_dir = Path(args[i + 1]).expanduser()
        except IndexError:
            sys.exit("--out needs a directory path")
        del args[i:i + 2]
    if "--txt" in args:
        as_txt = True
        args.remove("--txt")

    if backend not in ("local", "openai", "google"):
        sys.exit(f"unknown backend '{backend}'. Use: local | openai | google")

    files = [Path(a).expanduser() for a in args]
    if not files:
        sys.exit("No input files given.")

    label = {"local": WHISPER_MODEL, "openai": MODEL, "google": GEMINI_MODEL}[backend]
    print(f"backend: {backend} ({label})")
    for f in files:
        if not f.exists():
            print(f"skip missing: {f}")
            continue
        ext = f.suffix.lower()
        if ext not in AUDIO_EXTS and ext not in VIDEO_EXTS:
            print(f"skip unsupported type: {f}")
            continue
        print(f"\n== {f.name} ==")
        try:
            text, dur = transcribe_media(f, backend)
            write_note(f, text, dur, out_dir or f.parent, as_txt)
        except Exception as e:
            print(f"  ERROR: {e}")


if __name__ == "__main__":
    main()
