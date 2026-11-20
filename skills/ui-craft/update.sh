#!/usr/bin/env bash
#
# update.sh: fetch Emil Kowalski's guides (github.com/emilkowalski/skills, MIT) into ./emil.
#
# Upstream SKILL.md files land as emil/<name>/GUIDE.md, so harnesses don't register twenty extra
# skills. emil/SOURCE records the pinned commit. Exits 1 when an upstream guide has no row in the
# loadout table in SKILL.md, so you (or your agent) add the row. Committing is up to you.
set -uo pipefail

REPO=https://github.com/emilkowalski/skills
SKILL="$(cd "$(dirname "$0")" && pwd)"
EMIL="$SKILL/emil"

old=$(awk '{print $3}' "$EMIL/SOURCE" 2>/dev/null)
new=$(git ls-remote "$REPO" HEAD | cut -c1-7)
[ -n "$new" ] || { echo "could not reach $REPO"; exit 1; }
if [ "$old" = "$new" ]; then echo "current ($new)"; exit 0; fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 "$REPO" "$tmp/r" || exit 1

rm -rf "$EMIL" && mkdir -p "$EMIL"
cp -R "$tmp/r/skills/"* "$EMIL/"
cp "$tmp/r/LICENSE" "$EMIL/"
cp "$tmp/r/performance-cheatsheet.md" "$EMIL/" 2>/dev/null || true
for g in "$EMIL"/*/SKILL.md; do mv "$g" "${g%SKILL.md}GUIDE.md"; done
grep -rl 'SKILL\.md' "$EMIL" | while IFS= read -r f; do perl -pi -e 's/SKILL\.md/GUIDE.md/g' "$f"; done
echo "emilkowalski/skills @ $(git -C "$tmp/r" rev-parse --short=7 HEAD) ($(git -C "$tmp/r" log -1 --format=%cs))" >"$EMIL/SOURCE"
echo "emilkowalski/skills ${old:-none} -> $new"

rc=0
for d in "$EMIL"/*/; do
  n=$(basename "$d")
  grep -q "\`$n\`" "$SKILL/SKILL.md" || { echo "UNROUTED $n: add a loadout row in SKILL.md"; rc=1; }
done
exit "$rc"
