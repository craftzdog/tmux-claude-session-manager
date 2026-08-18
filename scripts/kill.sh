#!/usr/bin/env bash
# Kill the Claude behind a picker row, if it has one.
# Args: <kind> <pid>
#
# The aggregate rows have no single process to kill. fzf's execute-silent throws
# output away, so an unguarded `kill` here would fail invisibly and read as the
# keybinding being broken; say what happened instead.
set -uo pipefail

kind="${1:-}"
pid="${2:-}"

case "$kind" in
bg)
  tmux display-message 'Kill background agents from the `claude agents` view (enter)'
  ;;
note)
  tmux display-message 'That session is outside tmux — kill it where it runs'
  ;;
*)
  if [ -n "$pid" ] && [ "$pid" != '-' ]; then
    kill "$pid" 2>/dev/null || tmux display-message "Could not kill pid $pid"
  fi
  ;;
esac
