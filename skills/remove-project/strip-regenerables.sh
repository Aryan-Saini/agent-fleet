#!/usr/bin/env bash
# Delete everything regenerable from a project, without touching secrets.
#
#   strip-regenerables.sh <project>            # dry run, prints what would go
#   strip-regenerables.sh <project> --apply    # actually delete
#
# "Regenerable" is defined as "git ignores it", which catches node_modules,
# .next, .expo, ios/Pods, android/build, .venv, dist and every future
# equivalent with no hardcoded list to maintain.
#
# The trap: .env files, signing keys and local databases are gitignored too and
# are NOT regenerable. Two things protect them.
#   1. Protected files are found FIRST, from git's own list of ignored files.
#   2. A candidate directory is only removed wholesale when it contains no
#      protected file. If it does (e.g. ios/certs/), the script descends and
#      deletes around them instead.
# Do NOT try to do this with `git clean -e`: under -X those patterns add to the
# ignore rules, so they mark files for deletion rather than sparing them.
#
# Written for bash 3.2, which is what macOS ships.
set -euo pipefail

ROOT=${1:?usage: strip-regenerables.sh <project> [--apply]}
APPLY=${2:-}
cd "$ROOT"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "not a git repo: $ROOT. Strip it by hand, git clean can't help here" >&2; exit 1; }

# Basename patterns that must survive, even though git ignores them.
# Deliberately NOT matching `*.env`: that catches generated files like
# ios/.xcode.env and drags a 1.4G directory onto the slow path for nothing.
PROTECT_RE='(^|/)(\.env(\..*)?|.*\.(pem|p8|key|p12|keystore|jks|crt|cer|mobileprovision|sqlite|sqlite3|db)|google-services\.json|GoogleService-Info\.plist|service-account.*\.json|.*serviceaccount.*\.json|.*credentials.*\.json|\.npmrc|\.netrc|id_rsa.*|id_ed25519.*)$'

# Dependency trees are wholly reconstructible from a lockfile, so nothing
# inside them is ever worth protecting. Without this, vendored .pem fixtures
# shipped by packages would drag node_modules onto the file-by-file path.
VENDORED_RE='(^|/)(node_modules|\.pnpm|Pods|\.venv|venv|vendor|\.gradle|\.cxx)/'

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# Every ignored FILE (not collapsed into directories), split into keep and delete.
git ls-files -o -i --exclude-standard -z > "$WORK/ignored.z"
tr '\0' '\n' < "$WORK/ignored.z" | grep -E "$PROTECT_RE" | grep -Ev "$VENDORED_RE" | sort > "$WORK/kept" || true

echo "=== keeping (git ignores these, but they are not regenerable) ==="
[ -s "$WORK/kept" ] && sed 's/^/  /' "$WORK/kept" || echo "  (none found)"

# Candidates are what `git clean` would remove, collapsed to directories.
git clean -Xdn | sed 's/^Would remove //' | sed 's:/$::' | sort > "$WORK/candidates"

: > "$WORK/wipe"      # safe to rm -rf wholesale
: > "$WORK/descend"   # contains something protected; delete around it
while IFS= read -r c; do
  [ -n "$c" ] || continue
  if grep -qxF "$c" "$WORK/kept" 2>/dev/null; then
    continue                                   # the candidate IS a protected file
  elif [ -d "$c" ] && grep -qF -e "$c/" "$WORK/kept" 2>/dev/null; then
    echo "$c" >> "$WORK/descend"
  else
    echo "$c" >> "$WORK/wipe"
  fi
done < "$WORK/candidates"

echo
echo "=== deleting ==="
if [ -s "$WORK/wipe" ]; then
  while IFS= read -r d; do
    printf '  %8s  %s\n' "$(du -sh "$d" 2>/dev/null | cut -f1)" "$d"
  done < "$WORK/wipe"
else
  echo "  (nothing to strip)"
fi

if [ -s "$WORK/descend" ]; then
  echo
  echo "=== descending into (holds something protected) ==="
  sed 's/^/  /' "$WORK/descend"
fi

if [ "$APPLY" != "--apply" ]; then
  echo
  echo "dry run. re-run with --apply to delete."
  exit 0
fi

BEFORE=$(du -sh . | cut -f1)

# Whole subtrees with nothing worth saving in them.
while IFS= read -r d; do [ -n "$d" ] && rm -rf -- "$d"; done < "$WORK/wipe"

# Mixed subtrees: remove only the ignored files that are not protected.
if [ -s "$WORK/descend" ]; then
  while IFS= read -r prefix; do
    [ -n "$prefix" ] || continue
    tr '\0' '\n' < "$WORK/ignored.z" \
      | grep -E "^${prefix}/" \
      | grep -Ev "$PROTECT_RE" \
      | while IFS= read -r f; do rm -f -- "$f"; done || true
  done < "$WORK/descend"
  # Tidy up directories the file deletions emptied out.
  find . -type d -empty -not -path './.git/*' -delete 2>/dev/null || true
fi

# Confirm every protected file is still on disk.
MISSING=0
while IFS= read -r k; do
  [ -n "$k" ] || continue
  [ -e "$k" ] || { echo "LOST A PROTECTED FILE: $k" >&2; MISSING=1; }
done < "$WORK/kept"
[ "$MISSING" -eq 0 ] || { echo "strip removed something it should not have" >&2; exit 1; }

echo "stripped: $BEFORE -> $(du -sh . | cut -f1); $(grep -c . "$WORK/kept" 2>/dev/null || echo 0) protected file(s) intact"
