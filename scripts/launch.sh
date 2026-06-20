#!/usr/bin/env bash
# Launch (or re-attach to) an AI session for a directory, shown in a popup.
# Args: <dir> [origin-window-id] [provider]
#   dir/window are expanded by run-shell in the binding; provider defaults to
#   'claude' so the plain prefix+y binding behaves exactly as before.
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

# Don't open a popup while already inside one of our session popups (any
# provider). tmux can't nest popups cleanly, so refuse and tell the user.
if printf '%s' "$(tmux display-message -p '#S')" | grep -qE "^($(provider_prefixes_regex))"; then
  tmux display-message '🫪 Popup window already open'
  exit 0
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  # Fail loudly instead of spawning a session that dies instantly when the
  # provider CLI is missing. ${cmd%% *} strips arguments so we test the binary.
  if ! command -v "${cmd%% *}" >/dev/null 2>&1; then
    tmux display-message "tmux-claude-session-manager: '${cmd%% *}' not found in PATH"
    exit 0
  fi
  tmux new-session -d -s "$session" -c "$path" "$cmd"
fi

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t $session"
