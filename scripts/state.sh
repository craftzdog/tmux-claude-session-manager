#!/usr/bin/env bash
# Record a Claude Code session's state for the picker, via Claude Code hooks:
#   state.sh <working|waiting|idle>
#
# Claude Code hooks inherit the Claude process environment, so $TMUX_PANE is set
# whenever Claude runs inside tmux. Outside tmux this is a no-op.
#
# Where the state is stamped follows @claude_discover (see README):
#   session  (default)  on the tmux session — the launcher model.
#   pane                 on the tmux pane — so several Claudes sharing one session
#                        (each in its own window or pane) report independently.
[ -z "$TMUX_PANE" ] && exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

now="$(date +%s)"
state="${1:-idle}"

if [ "$(get_tmux_option @claude_discover 'session')" = 'pane' ]; then
  tmux set-option -p -t "$TMUX_PANE" @claude_state "$state" 2>/dev/null
  tmux set-option -p -t "$TMUX_PANE" @claude_state_at "$now" 2>/dev/null
else
  session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
  [ -z "$session" ] && exit 0
  tmux set-option -t "$session" @claude_state "$state"
  tmux set-option -t "$session" @claude_state_at "$now"
fi
exit 0
