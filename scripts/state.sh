#!/usr/bin/env bash
# Record a Claude Code session's state for the picker.
# Wire this into Claude Code hooks (see README):  state.sh <working|waiting|idle>
#
# Claude Code hooks inherit the Claude process environment, so $TMUX_PANE is set
# whenever Claude runs inside tmux. Outside tmux this is a no-op.
#
# State is recorded twice, so both picker scopes work without extra config:
#   - per-pane    (set -p): used by @claude_scope 'pane'/'auto'. Lets several
#                 Claude panes in the SAME tmux session track state independently.
#   - per-session: used by @claude_scope 'session' (default). Preserves the
#                 original behavior for dedicated `claude-*` sessions (one pane).
[ -z "$TMUX_PANE" ] && exit 0

state="${1:-idle}"
now="$(date +%s)"

# per-pane
tmux set-option -p -t "$TMUX_PANE" @claude_state "$state"
tmux set-option -p -t "$TMUX_PANE" @claude_state_at "$now"

# per-session (best-effort; harmless when several Claude panes share a session)
session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)
if [ -n "$session" ]; then
  tmux set-option -t "$session" @claude_state "$state"
  tmux set-option -t "$session" @claude_state_at "$now"
fi
exit 0
