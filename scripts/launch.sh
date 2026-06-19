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
read -r w h < <(popup_dims)

session="${prefix}$(session_hash "$path")"

if ! tmux has-session -t "$session" 2>/dev/null; then
  # Fail loudly instead of spawning a session that dies instantly when the
  # provider CLI is missing. ${cmd%% *} strips any arguments so we test the
  # binary, not the whole command line.
  if ! command -v "${cmd%% *}" >/dev/null 2>&1; then
    tmux display-message "claude-session-manager: '${cmd%% *}' not found in PATH"
    exit 0
  fi
  tmux new-session -d -s "$session" -c "$path" "$cmd"
fi

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t $session"
