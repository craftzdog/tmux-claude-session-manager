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
launch_menu_key="$(get_tmux_option @claude_launch_menu_key 'Y')"
list_key="$(get_tmux_option @claude_list_key 'u')"

# Launch (or re-attach to) a Claude session for the current pane's directory.
# #{pane_current_path} / #{window_id} are expanded by run-shell before the args
# reach the script.
tmux bind-key "$launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh '#{pane_current_path}' '#{window_id}' claude"

# Provider menu: pick which AI CLI to launch for the current pane's directory.
# Built from @claude_providers; each entry gets a numeric shortcut (1, 2, 3, …).
# With the default single-provider list this just launches Claude.
menu_args=()
i=0
for entry in $(get_providers); do
  i=$((i + 1))
  IFS=: read -r key _ label <<<"$entry"
  [ -z "$label" ] && label="$key"
  menu_args+=("$label" "$i" \
    "run-shell \"$CURRENT_DIR/scripts/launch.sh '#{pane_current_path}' '#{window_id}' $key\"")
done
tmux bind-key "$launch_menu_key" \
  display-menu -T ' AI Provider ' -x C -y C "${menu_args[@]}"

# Open the session picker. When pressed from inside a session popup, list.sh
# closes that popup first so the picker opens full-size on the outer client.
tmux bind-key "$list_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{client_name}'"
