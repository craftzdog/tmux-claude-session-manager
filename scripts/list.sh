#!/usr/bin/env bash
# Open the session picker in a popup.
#
# Two cases:
#   * Pressed from inside a session popup (the caller client is attached to a
#     managed session): open the picker *nested* on that same client, on top of
#     the current session. Nothing is closed, so the outer session is never
#     revealed — no flash. picker.sh then switches this client to the chosen
#     session in place; the nested popup closes, revealing the target.
#   * Pressed from a normal pane: open the picker on the host client and let
#     picker.sh morph it into the chosen session (the original behavior).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefixes_re="^($(provider_prefixes_regex))"
read -r w h < <(popup_dims)
caller="${1:-}"  # #{client_name} of the client that pressed the key

# A client NOT attached to a managed session — the outer client that hosts the
# picker in the non-nested case (and the morph fallback in picker.sh).
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v re="$prefixes_re" '$2 !~ re { print $1; exit }'
}

host="$(host_client)"
tmux set-option -g @ai_parent "$host"

caller_session=""
[ -n "$caller" ] &&
  caller_session=$(tmux display-message -p -t "$caller" '#{session_name}' 2>/dev/null)

if [ -n "$caller_session" ] && printf '%s' "$caller_session" | grep -qE "$prefixes_re"; then
  # Nested: draw the picker over the caller's session popup, no close/reopen.
  tmux set-option -g @ai_caller "$caller"
  tmux display-popup -c "$caller" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  # Normal pane: clear any stale caller so picker.sh uses the morph path.
  tmux set-option -gu @ai_caller 2>/dev/null || true
  if [ -n "$host" ]; then
    tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
  else
    tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
  fi
fi
