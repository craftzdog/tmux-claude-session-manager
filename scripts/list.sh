#!/usr/bin/env bash
# Open the session picker in a popup.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# The client that pressed the key, and the session it is currently attached to.
# Looked up by exact client_name match rather than "first client anywhere that
# looks nested" — with more than one client attached (e.g. a stray popup left
# open in another window), a global scan can grab an unrelated client's session
# and detach it instead of the one this invocation actually cares about.
me="${1:-}"
my_session="$(tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
  awk -v me="$me" '$1 == me { print $2; exit }')"

# A popup client is spawned by the tmux server itself, so its process ancestry
# reaches the server pid. A regular client (attached from a terminal) descends
# from the user's shell instead. Session name alone can't tell them apart: a
# claude-* session can also be entered by a plain attach (e.g. choose-tree),
# and detaching that client would kick the user out entirely.
is_popup_client() {
  local pid server_pid
  pid="$(tmux list-clients -F '#{client_name} #{client_pid}' 2>/dev/null |
    awk -v me="$1" '$1 == me { print $2; exit }')"
  server_pid="$(tmux display-message -p '#{pid}')"
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ "$pid" = "$server_pid" ] && return 0
  done
  return 1
}

in_popup=no
case "$my_session" in
"$prefix"*) is_popup_client "$me" && in_popup=yes ;;
esac

case "$in_popup" in
yes)
  # We are inside a session popup: close it, then reopen the picker on the
  # outer client that originally opened it.
  tmux detach-client -s "$my_session"
  for _ in $(seq 1 100); do
    tmux list-clients -F '#{session_name}' 2>/dev/null | grep -qx "$my_session" || break
    sleep 0.05
  done
  host="$(tmux show-options -gqv @claude_parent 2>/dev/null)"
  ;;
*)
  # Normal case: this client is already the host.
  host="$me"
  tmux set-option -g @claude_parent "$host"
  ;;
esac

# Host the picker on the outer client. -c is honored because that client has no
# popup open now; fall back to the default client if none was found.
if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
