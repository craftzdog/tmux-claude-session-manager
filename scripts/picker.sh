#!/usr/bin/env bash
# Interactive picker for running Claude sessions.
#
#   picker.sh           fzf picker; on enter, jump to the chosen Claude.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
#
# @claude_discover (default 'session') chooses what is listed:
#   session  tmux sessions named with @claude_session_prefix (the launcher model);
#            state per-session; enter resumes the session in the popup.
#   pane     every pane whose foreground command is @claude_command, however it was
#            started (tmuxinator, a manual `claude`, …); state per-pane; enter
#            switches to the pane's window and selects it.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

mode="$(get_tmux_option @claude_discover 'session')"
prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
cmd="$(get_tmux_option @claude_command 'claude')"

# set_icon <state> — sets $icon (coloured dot + label) and $rank (sort key).
set_icon() {
  case "$1" in
  waiting) icon=$'\033[33m●\033[0m waiting' rank=0 ;; # yellow - needs input
  idle) icon=$'\033[32m●\033[0m idle   ' rank=1 ;;    # green  - done, your turn
  working) icon=$'\033[31m●\033[0m working' rank=3 ;; # red    - busy, leave it
  *) icon=$'\033[90m●\033[0m   ?    ' rank=2 ;;       # grey   - unknown (no hook yet)
  esac
}

# Both modes emit the same columns, so the fzf/jump/kill code below is shared:
#   rank \t id \t dest \t icon \t age \t label
#     id    ctrl-x + preview target  (session name | pane id)
#     dest  enter target             (origin window | session:window)
# rank/id/dest are hidden (--with-nth=4,5,6); id/dest drive the actions. Sort by
# rank asc (attention-needed floats up) then age asc (just-finished on top); the
# age field's leading number is read by -k5,5n ("5m" -> 5, "-" -> 0).
emit_rows() {
  local now icon rank ago at pcmd id dest path title wname
  now=$(date +%s)
  if [ "$mode" = 'pane' ]; then
    tmux list-panes -a -F \
      '#{pane_current_command}	#{pane_id}	#{session_name}:#{window_index}	#{pane_current_path}	#{pane_title}	#{window_name}' \
      2>/dev/null |
      while IFS=$'\t' read -r pcmd id dest path title wname; do
        [ "$pcmd" = "$cmd" ] || continue
        set_icon "$(tmux show-options -pqv -t "$id" @claude_state 2>/dev/null)"
        at=$(tmux show-options -pqv -t "$id" @claude_state_at 2>/dev/null)
        if [ -n "$at" ]; then ago="$(((now - at) / 60))m"; else ago='-'; fi
        # Prefer Claude's pane title (it sets a task summary); fall back to window
        # name. Append the dir so same-titled panes stay distinguishable.
        printf '%s\t%s\t%s\t%s\t%5s\t%b\n' "$rank" "$id" "$dest" "$icon" "$ago" \
          "${title:-$wname}  \033[90m${path/#$HOME/~}\033[0m"
      done
  else
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}" |
      while IFS= read -r id; do
        set_icon "$(tmux show-options -qv -t "$id" @claude_state 2>/dev/null)"
        at=$(tmux show-options -qv -t "$id" @claude_state_at 2>/dev/null)
        dest=$(tmux show-options -qv -t "$id" @claude_origin 2>/dev/null)
        path=$(tmux display-message -p -t "$id" '#{pane_current_path}' 2>/dev/null)
        if [ -n "$at" ]; then ago="$(((now - at) / 60))m"; else ago='-'; fi
        printf '%s\t%s\t%s\t%s\t%5s\t%s\n' "$rank" "$id" "$dest" "$icon" "$ago" \
          "${path/#$HOME/~}"
      done
  fi | sort -t$'\t' -k1,1n -k5,5n
}

[ "${1:-}" = '--list' ] && {
  emit_rows
  exit 0
}

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-claude-session-manager: fzf is required for the picker"
  exit 0
fi

# ctrl-x removes the highlighted entry: a pane in pane mode, a session otherwise.
if [ "$mode" = 'pane' ]; then kill_cmd='kill-pane'; else kill_cmd='kill-session'; fi

self="${BASH_SOURCE[0]}"
export FZF_DEFAULT_OPTS=''
sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=4,5,6 \
  --reverse --cycle --header='Claude sessions · enter: jump · ctrl-x: kill' \
  --preview="tmux capture-pane -ept {2}" --preview-window='right,62%,wrap' \
  --bind="ctrl-x:execute-silent(tmux $kill_cmd -t {2})+reload($self --list)")

[ -z "$sel" ] && exit 0
id=$(printf '%s' "$sel" | cut -f2)
dest=$(printf '%s' "$sel" | cut -f3)
parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)

if [ "$mode" = 'pane' ]; then
  # Move the host client to the pane's window, then select the pane. The popup
  # closes as picker.sh exits, revealing the target underneath.
  if [ -n "$parent" ]; then
    tmux switch-client -c "$parent" -t "$dest" 2>/dev/null
  else
    tmux switch-client -t "$dest" 2>/dev/null
  fi
  tmux select-pane -t "$id" 2>/dev/null
else
  # Move the parent client to the session's origin window (best-effort), then
  # resume the session in THIS popup over it.
  [ -n "$dest" ] && [ -n "$parent" ] &&
    tmux switch-client -c "$parent" -t "$dest" 2>/dev/null
  tmux attach-session -t "$id"
fi
