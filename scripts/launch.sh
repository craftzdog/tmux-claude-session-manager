#!/usr/bin/env bash
# Launch (or re-attach to) an AI session for a directory, shown in a popup.
# Args: <dir> [origin-window-id] [provider]
#   dir/window are expanded by run-shell in the binding; provider defaults to
#   'claude' so the legacy prefix+y binding keeps working unchanged.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

path="${1:-$PWD}"
window="${2:-}"
provider="${3:-claude}"

prefix="$(provider_prefix "$provider")"
cmd="$(provider_command "$provider")"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

session="${prefix}$(session_hash "$path")"

tmux has-session -t "$session" 2>/dev/null \
  || tmux new-session -d -s "$session" -c "$path" "$cmd"

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t $session"
