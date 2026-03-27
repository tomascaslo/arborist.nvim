#!/bin/bash
# Claude Code Stop hook — pushes to Neovim's notification queue
# when Claude finishes and is waiting for input.
# Part of arborist.nvim

INPUT=$(cat)

# Avoid infinite loops
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# Escape for Lua strings
CWD_ESC=$(echo "$CWD" | sed 's/\\/\\\\/g; s/"/\\"/g')
SID_ESC=$(echo "$SESSION_ID" | sed 's/\\/\\\\/g; s/"/\\"/g')

# Push notification to all running Neovim instances
# macOS
for sock in "${TMPDIR}"nvim.*/*/nvim.*.0; do
  [ -S "$sock" ] || continue
  nvim --server "$sock" --remote-expr \
    "luaeval('_claude_push_notification(\"$CWD_ESC\", \"$SID_ESC\")')" \
    2>/dev/null &
done

# Linux
for sock in /run/user/*/nvim.*/0 /tmp/nvim.*/0; do
  [ -S "$sock" ] || continue
  nvim --server "$sock" --remote-expr \
    "luaeval('_claude_push_notification(\"$CWD_ESC\", \"$SID_ESC\")')" \
    2>/dev/null &
done

wait
exit 0
