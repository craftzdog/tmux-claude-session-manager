#!/usr/bin/env bash
# Render the fzf preview for one picker row.
# Args: <kind> <pane-id> <pid(s)>
#
# Only pane-backed rows have a pane to capture; the aggregate rows describe
# themselves instead. Without this dispatch a `capture-pane` aimed at the
# background row's placeholder id would fail into a blank box that looks like a
# rendering bug.
set -uo pipefail

kind="${1:-}"
pane="${2:-}"
pids="${3:-}"

case "$kind" in
bg)
  printf '\033[1mBackground agents\033[0m — enter opens the `claude agents` view.\n\n'
  claude agents --json 2>/dev/null |
    jq -r '
      [.[] | select(.kind == "background")] as $bg
      | if ($bg | length) == 0 then
          "No live background agents."
        else
          ($bg | sort_by(.state != "blocked", .startedAt)
               | map("  \(if .state == "blocked" then "●" else "·" end) \(.state | .[0:8] | . + (" " * (8 - length))) \(.name // .id)")
               | join("\n"))
        end'
  ;;
note)
  printf '\033[1mRunning outside tmux\033[0m — no pane to jump to.\n\n'
  printf 'Reachable only where they were started (a plain shell, another\n'
  printf 'multiplexer, or a detached login). Listed here so the overview\n'
  printf 'never hides a live session.\n\n'
  [ -n "$pids" ] && [ "$pids" != '-' ] && ps -o pid=,lstart=,args= -p "$pids" 2>/dev/null
  ;;
*)
  tmux capture-pane -ept "$pane" 2>/dev/null
  ;;
esac
