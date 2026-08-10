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

# Launch (or re-attach to) a Claude session for the current pane's directory.
# #{pane_current_path} / #{window_id} are expanded by run-shell before the args
# reach the script.
tmux bind-key "$launch_key" \
  run-shell "$CURRENT_DIR/scripts/launch.sh '#{q:pane_current_path}' '#{q:window_id}'"

# Open the session picker. When pressed from inside a session popup, list.sh
# closes that popup first so the picker opens full-size on the outer client.
tmux bind-key "$list_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{q:client_name}'"

# Sound notifications: plays a sound when a Claude session starts waiting
# on you, and another when one finishes while you're not looking at it.
# Event-driven via Claude Code hooks (scripts/hook-notify.sh), not a poll
# loop; this just (re)registers those hooks in ~/.claude/settings.json.
# Idempotent, so it's safe to fire on every config reload. The hooks stay
# registered even with @claude_notify_sound off; hook-notify.sh checks that
# option itself and no-ops rather than playing anything.
"$CURRENT_DIR/scripts/install-notify-hooks.sh" --apply >/dev/null 2>&1 &
