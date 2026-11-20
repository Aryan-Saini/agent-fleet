#!/usr/bin/env bash
# Give a Finder folder a custom icon.
#
#   set-folder-icon.sh <source.png> <folder>
#
# Standard macOS method: a `.icon.icns` inside the
# folder, the icns copied into the resource fork of an invisible `Icon\r` file,
# and the folder's custom-icon Finder bit set. Both artifacts should be
# gitignored (`.icon.icns` and `Icon?`).
set -euo pipefail

SRC=${1:?usage: set-folder-icon.sh <source.png> <folder>}
FOLDER=${2:?usage: set-folder-icon.sh <source.png> <folder>}
[ -f "$SRC" ] || { echo "no such image: $SRC" >&2; exit 1; }
[ -d "$FOLDER" ] || { echo "no such folder: $FOLDER" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A square source keeps every rung of the iconset from being letterboxed.
python3 - "$SRC" "$WORK/square.png" <<'PY'
import sys
from PIL import Image

src = Image.open(sys.argv[1]).convert("RGBA")
src = src.crop(src.getbbox())          # drop the transparent margin
side = int(max(src.size) / 0.92)       # then re-pad it evenly
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(src, ((side - src.width) // 2, (side - src.height) // 2), src)
canvas.resize((1024, 1024), Image.LANCZOS).save(sys.argv[2])
PY

mkdir "$WORK/icon.iconset"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$WORK/square.png" --out "$WORK/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/square.png" --out "$WORK/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/icon.iconset" -o "$WORK/icon.icns"

cp "$WORK/icon.icns" "$FOLDER/.icon.icns"
sips -i "$FOLDER/.icon.icns" >/dev/null
DeRez -only icns "$FOLDER/.icon.icns" > "$WORK/icon.rsrc"
printf '' > "$FOLDER/Icon"$'\r'
Rez -append "$WORK/icon.rsrc" -o "$FOLDER/Icon"$'\r'
SetFile -a C "$FOLDER"
SetFile -a V "$FOLDER/Icon"$'\r'

GetFileInfo "$FOLDER" | grep '^attributes' | grep -q 'C' \
  && echo "custom icon set on $FOLDER" \
  || { echo "custom-icon bit did not stick on $FOLDER" >&2; exit 1; }
