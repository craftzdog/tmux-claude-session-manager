#!/usr/bin/env bash
# tmux-claude-session-manager
#
# List, monitor status, and jump across nested Claude Code sessions from a
# single popup. tpm runs this file as an executable on tmux startup; it reads
# user options (with sensible defaults) and installs the key bindings.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

launch_key="$(get_tmux_option @claude_launch_key 'y')"
list_key="$(get_tmux_option @claude_list_key 'u')"
# Per-key prefix toggle. 'on' (default) keeps the historical prefix+<key>
# behaviour; 'off' installs a root-table binding (tmux bind-key -n) so the key
# fires without the prefix. Pair 'off' with a modifier key such as 'M-y' — a
# bare letter in the root table would hijack normal typing.
launch_prefix="$(get_tmux_option @claude_launch_prefix 'on')"
list_prefix="$(get_tmux_option @claude_list_prefix 'on')"

# bind_claude <key> <use_prefix on|off> <tmux command...>
# Wraps bind-key so a key can live in either the prefix table or the root
# table (-n, no prefix) depending on the per-key option.
bind_claude() {
  key="$1"; use_prefix="$2"; shift 2
  if [ "$use_prefix" = 'off' ]; then
    tmux bind-key -n "$key" "$@"
  else
    tmux bind-key "$key" "$@"
  fi
}

# Launch (or re-attach to) a Claude session for the current pane's directory.
# #{pane_current_path} / #{window_id} are expanded by run-shell before the args
# reach the script.
bind_claude "$launch_key" "$launch_prefix" \
  run-shell "$CURRENT_DIR/scripts/launch.sh '#{pane_current_path}' '#{window_id}'"

# Open the session picker. When pressed from inside a session popup, list.sh
# closes that popup first so the picker opens full-size on the outer client.
bind_claude "$list_key" "$list_prefix" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{client_name}'"
