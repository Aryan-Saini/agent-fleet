#!/bin/bash
# Checks which skill Haiku and Sonnet invoke for each prompt, without letting them act.
# Usage: trigger-eval.sh [model...]   (default: claude-haiku-5-5 claude-sonnet-5-5)
#
# Safety: the model gets ONLY the Skill tool (--tools Skill), no MCP servers (--strict-mcp-config
# with no --mcp-config), a fresh temp working dir, one turn, and no saved session. Loading a skill
# only reads its SKILL.md, so nothing can run, click, screenshot or write. An earlier version only
# disallowed Bash/Write/Edit, left the cua-driver MCP tools reachable, and a negative case took a
# real screenshot onto the Desktop.
set -uo pipefail

MODELS=("$@"); [ ${#MODELS[@]} -gt 0 ] || MODELS=(claude-haiku-5-5 claude-sonnet-5-5)
# "NEG " marks prompts that should NOT trigger codex-image-creation.
PROMPTS=(
  "generate an image of a golden retriever surfing a big wave"
  "use codex to get me an image of a minimalist fox logo"
  "can you make a thumbnail for my youtube video about learning rust"
  "remove the background from /tmp/photo.png so it's transparent"
  "I need a hero picture for the landing page, a city skyline at dusk"
  "draw me a wallpaper of snowy mountains"
  "make a cover image for my blog post about sleep"
  "NEG make a bar chart of these numbers: 3, 5, 7"
  "NEG take a screenshot of my desktop"
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

run() {
  local model=$1 raw=$2 p=${2#NEG } want=YES out hit=no
  [ "$raw" != "$p" ] && want=no
  out=$(timeout 180 claude -p "$p" --model "$model" --max-turns 1 --tools Skill --strict-mcp-config \
      --no-session-persistence --output-format stream-json --verbose 2>/dev/null \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
             | "\(.name):\(.input.skill // "")"' 2>/dev/null | tr '\n' ' ')
  echo "$out" | grep -q 'Skill:codex-image-creation' && hit=YES
  local mark=PASS; [ "$hit" = "$want" ] || mark=FAIL
  printf '%s | %-18s | %-62s | %s\n' "$mark" "$model" "${raw:0:62}" "$out"
}

for m in "${MODELS[@]}"; do
  for p in "${PROMPTS[@]}"; do run "$m" "$p" & done
done
wait
