#!/usr/bin/env bash
# Launch (or re-attach to) a Codex session for a directory, shown in a popup.
# Args: <dir> [origin-window-id]   (both expanded by run-shell in the binding)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

path="${1:-$PWD}"
window="${2:-}"

prefix="$(get_tmux_option @codex_session_prefix 'codex-')"
cmd="$(get_tmux_option @codex_command 'codex')"
args="$(get_tmux_option @codex_args '')"
resume="$(get_tmux_option @codex_resume 'on')"

# Managed sessions keep Codex's status and project in the pane title so the
# picker can distinguish working, waiting, and idle agents without private APIs.
base_cmd="$cmd -c 'tui.terminal_title=[\"status\",\"project\"]'"
w="$(get_tmux_option @codex_popup_width '90%')"
h="$(get_tmux_option @codex_popup_height '90%')"

path_hash="$(session_hash "$path")"
session="${prefix}${path_hash}"

# A durable marker records that this project has had a managed Codex session.
# On later tmux launches, Codex resumes the newest saved conversation for the
# same working directory instead of silently replacing it with a blank chat.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-codex-session-manager"
resume_marker="$state_dir/$path_hash"

# persist_resume_marker records plugin ownership without copying any Codex
# conversation data into the manager's state directory.
persist_resume_marker() {
  mkdir -p "$state_dir"
  touch "$resume_marker"
}

# Only sessions explicitly created by this plugin count as managed popups. A
# normal tmux session is allowed to share the configurable codex- name prefix.
current_session="$(tmux display-message -p '#S')"
current_is_managed="$(tmux show-options -qv -t "$current_session" @codex_managed 2>/dev/null)"
if [ "$current_is_managed" = 1 ]; then
  # Pressing the launch key in a session created by an older plugin version
  # registers it for persisted resume before preserving the existing popup.
  [ "$resume" = 'off' ] || persist_resume_marker
  tmux display-message '🫪 Popup window already open'
  exit 0
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  [ -d "$path" ] || {
    tmux display-message "tmux-codex-session-manager: $path no longer exists"
    exit 0
  }

  # The first managed launch starts a new chat. Once the project marker exists,
  # `resume --last` restores Codex's most recent conversation from this cwd.
  launch_cmd="$base_cmd"
  if [ "$resume" != 'off' ] && [ -f "$resume_marker" ]; then
    launch_cmd="$launch_cmd resume --last"
  fi
  [ -n "$args" ] && launch_cmd="$launch_cmd $args"
  tmux new-session -d -s "$session" -c "$path" "$launch_cmd"
fi

# Tag new and pre-existing plugin sessions so popup detection and picker routing
# never have to infer ownership from a user-controlled session name.
tmux set-option -t "$session" @codex_managed 1

# Persist only plugin ownership, never transcript contents. Registering an
# already-running managed session also migrates sessions created before resume
# support was installed.
if [ "$resume" != 'off' ]; then
  persist_resume_marker
fi

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @codex_origin "$window"

tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t '$session'"
