#!/usr/bin/env bash
# Interactive picker for running Claude sessions / panes.
#
#   picker.sh           fzf picker; on enter, jumps to the chosen Claude.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
#
# Scope is controlled by @claude_scope (default 'session'):
#   session  list dedicated `claude-*` sessions created by the launcher (prefix+y).
#   pane     list every pane whose foreground command is the Claude CLI, across
#            all tmux sessions (works when you run Claude as a pane in your own
#            project sessions, several per session).
#   auto     'session' if any `claude-*` session exists, otherwise 'pane'.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
scope="$(get_tmux_option @claude_scope 'session')"
cmd="$(get_tmux_option @claude_command 'claude')"
# Foreground command name to match in pane scope: basename of @claude_command,
# minus any arguments (e.g. '/opt/homebrew/bin/claude --foo' -> 'claude').
cmd_base="${cmd##*/}"
cmd_base="${cmd_base%% *}"

# Resolve 'auto' to a concrete scope: use dedicated-session view if the launcher
# has created any `claude-*` sessions, otherwise fall back to scanning panes.
if [ "$scope" = 'auto' ]; then
  if tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -q "^${prefix}"; then
    scope='session'
  else
    scope='pane'
  fi
fi

# state_icon <state> -> sets globals `icon` and `rank` (shared by both scopes).
state_icon() {
  case "$1" in
  waiting) icon=$'\033[33m●\033[0m waiting' rank=0 ;; # yellow - needs input
  idle) icon=$'\033[32m●\033[0m idle   ' rank=1 ;;    # green  - done, your turn
  working) icon=$'\033[31m●\033[0m working' rank=3 ;; # red    - busy, leave it
  *) icon=$'\033[90m●\033[0m   ?    ' rank=2 ;;       # grey   - unknown (no hook yet)
  esac
}

# rank asc (attention-needed floats up), then age asc so the one that finished
# just now sits at the top of its group. -k4,4n reads the leading number of the
# age field ("5m" -> 5; "-" -> 0).  Column 2 is the jump/preview/kill target.
emit_rows_session() {
  local now s state at path icon rank ago
  now=$(date +%s)
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}" | while IFS= read -r s; do
    state=$(tmux show-options -qv -t "$s" @claude_state 2>/dev/null)
    at=$(tmux show-options -qv -t "$s" @claude_state_at 2>/dev/null)
    path=$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)
    state_icon "$state"
    if [ -n "$at" ]; then ago="$(((now - at) / 60))m"; else ago='-'; fi
    printf '%s\t%s\t%s\t%5s\t%s\n' "$rank" "$s" "$icon" "$ago" "${path/#$HOME/~}"
  done | sort -t$'\t' -k1,1n -k4,4n
}

emit_rows_pane() {
  local now pane sess win path state at icon rank ago
  now=$(date +%s)
  tmux list-panes -a -F '#{pane_id}	#{pane_current_command}	#{session_name}	#{window_index}	#{pane_current_path}' 2>/dev/null |
    awk -F'\t' -v c="$cmd_base" '$2 == c { print $1 "\t" $3 "\t" $4 "\t" $5 }' |
    while IFS=$'\t' read -r pane sess win path; do
      state=$(tmux show-options -pqv -t "$pane" @claude_state 2>/dev/null)
      at=$(tmux show-options -pqv -t "$pane" @claude_state_at 2>/dev/null)
      state_icon "$state"
      if [ -n "$at" ]; then ago="$(((now - at) / 60))m"; else ago='-'; fi
      # target column is the pane id; label shows session:window + path
      printf '%s\t%s\t%s\t%5s\t%s\n' "$rank" "$pane" "$icon" "$ago" "${sess}:${win}  ${path/#$HOME/~}"
    done | sort -t$'\t' -k1,1n -k4,4n
}

emit_rows() {
  if [ "$scope" = 'pane' ]; then emit_rows_pane; else emit_rows_session; fi
}

[ "${1:-}" = '--list' ] && {
  emit_rows
  exit 0
}

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-claude-session-manager: fzf is required for the picker"
  exit 0
fi

if [ "$scope" = 'pane' ]; then
  kill_cmd='tmux kill-pane -t {2}'
  header='Claude panes · enter: jump · ctrl-x: kill'
else
  kill_cmd='tmux kill-session -t {2}'
  header='Claude sessions · enter: jump · ctrl-x: kill'
fi

self="${BASH_SOURCE[0]}"
export FZF_DEFAULT_OPTS=''
sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=3,4,5 \
  --reverse --cycle --header="$header" \
  --preview="tmux capture-pane -ept {2}" --preview-window='right,62%,wrap' \
  --bind="ctrl-x:execute-silent($kill_cmd)+reload($self --list)")

[ -z "$sel" ] && exit 0
target=$(printf '%s' "$sel" | cut -f2)
parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)

if [ "$scope" = 'pane' ]; then
  # The target is a real pane in one of the user's sessions. Move the underlying
  # parent client there (session:window), focus the pane, then let this popup
  # close on exit. No attach — the pane already lives in a normal session.
  dest=$(tmux display-message -p -t "$target" '#{session_name}:#{window_index}' 2>/dev/null)
  if [ -n "$parent" ] && [ -n "$dest" ]; then
    tmux switch-client -c "$parent" -t "$dest" 2>/dev/null
  elif [ -n "$dest" ]; then
    tmux switch-client -t "$dest" 2>/dev/null
  fi
  tmux select-pane -t "$target" 2>/dev/null
  exit 0
fi

# session scope: move the underlying parent client to the session's origin window
# (best-effort), then resume the session in THIS popup over it. Falls back to
# resuming over the current window when origin/parent are unknown.
origin=$(tmux show-options -qv -t "$target" @claude_origin 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux attach-session -t "$target"
