#!/usr/bin/env bash
# Launch (or re-attach to) an opencode session for a directory, shown in a popup.
# Args: <dir> [origin-window-id]   (both expanded by run-shell in the binding)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

path="${1:-$PWD}"
window="${2:-}"

prefix="$(get_tmux_option @opencode_session_prefix 'opencode-')"
cmd="$(get_tmux_option @opencode_command 'opencode')"
w="$(get_tmux_option @opencode_popup_width '90%')"
h="$(get_tmux_option @opencode_popup_height '90%')"

session="${prefix}$(session_hash "$path")"

if [[ "$(tmux display-message -p '#S')" == "$prefix"* ]]; then
  tmux display-message '🫪 Popup window already open'
  exit 0
fi

# Calculate port from path hash 
path_hash=$(printf '%s' "$path" | md5sum | cut -c1-8)
port=$((16#${path_hash:0:4} % 55536 + 10000))

tmux has-session -t "$session" 2>/dev/null ||
  tmux new-session -d -s "$session" -c "$path" "$cmd --port $port"

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @opencode_origin "$window"

tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t $session"
