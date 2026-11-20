#!/bin/bash
# codex-image-creation: generate or edit an AI image by calling a CLIProxyAPI hub's OpenAI-style
# image routes directly. The hub forwards to ChatGPT's Codex image endpoint on a signed-in
# subscription account: no OpenAI API key, no API credits, no Codex agent turn.
# Without a hub, set OPENAI_API_KEY and it calls api.openai.com instead (billed per image).
# Usage: gen.sh "<image prompt>" "<name.png | output path>" [--ref <image>]...
#   --ref   attach an image to edit or to use as a reference (repeatable, max 5)
# The original always lands in $IMAGE_DIR (default ~/Pictures/generated). A bare filename goes
# straight there; a path anywhere else gets the original in $IMAGE_DIR plus a copy at that path.
# A prompt containing "transparent background" asks for a real alpha channel.

set -euo pipefail

PROMPT="${1:-}"
OUTPATH="${2:-}"
shift 2 2>/dev/null || true

if [ -z "$PROMPT" ] || [ -z "$OUTPATH" ]; then
  echo 'usage: gen.sh "<image prompt>" "<output path>" [--ref <image>]...' >&2
  exit 2
fi

# The subscription endpoint ignores the model name and treats any quality except "low" as auto,
# so these are fixed rather than options. Through the hub the model only has to be a name the hub
# recognises (see its /v1/models). With an API key it is the model you are billed for.
MODEL="${IMAGE_MODEL:-gpt-image-1}"
QUALITY="auto"

REFS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ref)
      [ -n "${2:-}" ] || { echo "--ref needs a path" >&2; exit 2; }
      REF="${2/#\~/$HOME}"
      [ -f "$REF" ] || { echo "reference image not found: $REF" >&2; exit 2; }
      REFS+=("$REF")
      shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ ${#REFS[@]} -le 5 ] || { echo "at most 5 --ref images" >&2; exit 2; }

# Every original is kept here, whatever the destination, so nothing generated is ever lost.
GENDIR="${IMAGE_DIR:-$HOME/Pictures/generated}"
mkdir -p "$GENDIR"

# A bare filename means IMAGES/generated. Otherwise expand ~ and resolve the destination; a folder
# (trailing slash or existing dir) means "name it for me", since dirname/basename would otherwise
# write an extension-less file in the parent.
case "$OUTPATH" in */*|\~*) ;; *) OUTPATH="$GENDIR/$OUTPATH" ;; esac
OUTPATH="${OUTPATH/#\~/$HOME}"
case "$OUTPATH" in */) OUTPATH="${OUTPATH}image-$(date +%Y%m%d-%H%M%S).png" ;; esac
[ -d "$OUTPATH" ] && OUTPATH="${OUTPATH%/}/image-$(date +%Y%m%d-%H%M%S).png"
mkdir -p "$(dirname "$OUTPATH")"
OUTPATH="$(cd "$(dirname "$OUTPATH")" && pwd)/$(basename "$OUTPATH")"

# ORIGINAL is where the image is written; COPY is the extra destination, if any.
COPY=""
case "$OUTPATH" in
  "$(cd "$GENDIR" && pwd)"/*) ORIGINAL="$OUTPATH" ;;
  *)
    COPY="$OUTPATH"
    # Name the original after the destination folder so generic names (.t3-icon.png, icon.png)
    # stay visible and distinct: ~/code/foo/.t3-icon.png -> foo-t3-icon.png.
    BASE="$(basename "$OUTPATH")"
    STEM="$(basename "$(dirname "$OUTPATH")")-${BASE#.}"
    ORIGINAL="$GENDIR/$STEM"
    # Don't clobber an unrelated earlier image that happens to share the name.
    [ -e "$ORIGINAL" ] && ORIGINAL="$GENDIR/${STEM%.*}-$(date +%Y%m%d-%H%M%S).png" ;;
esac

# Hub address and key come from this machine's Codex config ([model_providers.cliproxy]), so the
# controller (hub's tailnet URL) and the worker running the hub (127.0.0.1) each use their own
# route. No hub configured: fall back to the OpenAI API with OPENAI_API_KEY.
CFG="$HOME/.codex/config.toml"
section() { [ -f "$CFG" ] || return 0; sed -n '/^\[model_providers\.cliproxy\]/,/^\[/p' "$CFG"; }
HUB="$(section | sed -n 's/^base_url *= *"\(.*\)"/\1/p' | head -1)"
TOKEN="$(section | sed -n 's/^experimental_bearer_token *= *"\(.*\)"/\1/p' | head -1)"
if [ -z "$HUB" ] || [ -z "$TOKEN" ]; then
  [ -n "${OPENAI_API_KEY:-}" ] || { echo "no cliproxy base_url/token in $CFG and no OPENAI_API_KEY" >&2; exit 1; }
  HUB="https://api.openai.com/v1"; TOKEN="$OPENAI_API_KEY"
fi

BACKGROUND="auto"
echo "$PROMPT" | grep -qi 'transparent background' && BACKGROUND="transparent"

RESP="$(mktemp)"
trap 'rm -f "$RESP"' EXIT

echo ">> $MODEL ($QUALITY, background $BACKGROUND) -> $ORIGINAL${COPY:+ (copy to $COPY)}"
[ ${#REFS[@]} -gt 0 ] && printf '>> Reference: %s\n' "${REFS[@]}"
START=$(date +%s)

# One request. Prints the HTTP status; the body lands in $RESP.
request() {
  if [ ${#REFS[@]} -gt 0 ]; then
    local FORM=(--form-string "model=$MODEL" --form-string "quality=$QUALITY"
                --form-string "background=$BACKGROUND" --form-string "prompt=$PROMPT")
    for R in "${REFS[@]}"; do FORM+=(-F "image[]=@$R"); done
    curl -sS -o "$RESP" -w '%{http_code}' --max-time 300 \
      -H "Authorization: Bearer $TOKEN" "${FORM[@]}" "$HUB/images/edits"
  else
    local BODY
    BODY=$(jq -n --arg m "$MODEL" --arg q "$QUALITY" --arg b "$BACKGROUND" --arg p "$PROMPT" \
      '{model: $m, quality: $q, background: $b, prompt: $p, output_format: "png", n: 1}')
    curl -sS -o "$RESP" -w '%{http_code}' --max-time 300 \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d "$BODY" "$HUB/images/generations"
  fi
}

# Long, high-quality generations occasionally come back as a 5xx; one retry clears it.
CODE=$(request || true)
case "$CODE" in 5*|000) echo ">> HTTP $CODE, retrying once"; CODE=$(request || true) ;; esac

B64="$(jq -r '.data[0].b64_json // empty' "$RESP" 2>/dev/null || true)"
if [ "$CODE" != 200 ] || [ -z "$B64" ]; then
  echo "FAILED: $HUB returned HTTP $CODE" >&2
  jq -r '.error.message // .detail // .' "$RESP" 2>/dev/null | head -c 600 >&2 || head -c 600 "$RESP" >&2
  echo >&2
  exit 1
fi
printf '%s' "$B64" | base64 -d > "$ORIGINAL"
[ -n "$COPY" ] && cp "$ORIGINAL" "$COPY"

echo "---"
# IMAGE: and COPY: carry bare absolute paths so the calling agent can use them as-is.
echo "OK ($(( $(date +%s) - START ))s, served as $(jq -r '"\(.quality) \(.size)"' "$RESP"))"
echo "IMAGE: $ORIGINAL"
[ -n "$COPY" ] && echo "COPY: $COPY"
file "$ORIGINAL"
# "it exists" is not "it is what was asked": print real dimensions and alpha
# (sips is macOS only; on Linux the `file` line above carries the dimensions)
sips -g pixelWidth -g pixelHeight -g hasAlpha "$ORIGINAL" 2>/dev/null | tail -n +2 || true
