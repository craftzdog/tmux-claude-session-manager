#!/usr/bin/env bash
# Interactive picker for running Claude sessions.
#
#   picker.sh           fzf picker; on enter, switches the parent client to the
#                       chosen session's origin window and resumes it in the popup.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"

emit_rows() {
  local now s state at path icon rank ago
  now=$(date +%s)
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}" | while IFS= read -r s; do
    state=$(tmux show-options -qv -t "$s" @claude_state 2>/dev/null)
    at=$(tmux show-options -qv -t "$s" @claude_state_at 2>/dev/null)
    path=$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)
    case "$state" in
      waiting) icon=$'\033[33m●\033[0m waiting' rank=0 ;; # yellow - needs input
      idle)    icon=$'\033[32m●\033[0m idle   ' rank=1 ;; # green  - done, your turn
      working) icon=$'\033[31m●\033[0m working' rank=3 ;; # red    - busy, leave it
      *)       icon=$'\033[90m●\033[0m   ?    ' rank=2 ;; # grey   - unknown (no hook yet)
    esac
    if [ -n "$at" ]; then ago="$(( (now - at) / 60 ))m"; else ago='-'; fi
    # rank \t session \t icon \t path \t age   (rank/session hidden via --with-nth)
    printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "$s" "$icon" "${path/#$HOME/~}" "$ago"
  done | sort -n # attention-needed (waiting, idle) float to the top
}

[ "${1:-}" = '--list' ] && { emit_rows; exit 0; }

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-claude-session-manager: fzf is required for the picker"
  exit 0
fi

self="${BASH_SOURCE[0]}"
export FZF_DEFAULT_OPTS=''
sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=3,4,5 \
  --reverse --cycle --header='Claude sessions · enter: jump · ctrl-x: kill' \
  --preview="tmux capture-pane -ept {2}" --preview-window='right,62%,wrap' \
  --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload($self --list)")

[ -z "$sel" ] && exit 0
target=$(printf '%s' "$sel" | cut -f2)

# Move the underlying parent client to the session's origin window (best-effort),
# then resume the session in THIS popup over it. Falls back to resuming over the
# current window when origin/parent are unknown.
origin=$(tmux show-options -qv -t "$target" @claude_origin 2>/dev/null)
parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] && \
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux attach-session -t "$target"
