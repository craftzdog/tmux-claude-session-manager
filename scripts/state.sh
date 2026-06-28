#!/usr/bin/env bash
# Record an opencode session's state on its tmux session, for the picker.
# Wire this into opencode hooks (see README):  state.sh <busy|idle>
#
# Opencode hooks receive JSON on stdin with session_id.
# Outside tmux this is a no-op.
[ -z "$TMUX_PANE" ] && exit 0

# Read JSON from stdin (opencode passes context)
input=$(cat)

# Extract session_id from JSON (if available)
session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)

# Get the tmux session name from the current pane
session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
[ -z "$session" ] && exit 0

tmux set-option -t "$session" @opencode_state "${1:-idle}"
tmux set-option -t "$session" @opencode_state_at "$(date +%s)"
exit 0
