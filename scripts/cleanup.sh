#!/usr/bin/env bash
# Garbage-collect Claude sessions whose origin window is gone.
#
# Wired to the `window-unlinked` hook (opt-in via @claude_kill_on_origin_close):
# whenever a window closes, any claude-<hash> session whose @claude_origin points
# at a window that no longer exists is killed. A session launched without an
# origin window (no @claude_origin) is left alone.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"

# Every live window id across all sessions, one per line.
live="$(tmux list-windows -a -F '#{window_id}' 2>/dev/null)"

tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}" | while IFS= read -r s; do
  origin="$(tmux show-options -qv -t "$s" @claude_origin 2>/dev/null)"
  [ -z "$origin" ] && continue
  # Origin window still open? keep the session.
  printf '%s\n' "$live" | grep -qxF "$origin" && continue
  tmux kill-session -t "$s" 2>/dev/null
done
