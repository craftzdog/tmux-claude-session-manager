#!/usr/bin/env bash
# Open the session picker in a popup.
#
# When invoked from inside a session popup, the picker must reopen full-size on
# the outer (host) client — a popup-in-popup would be cramped. We do the swap in
# a single tmux command: `display-popup -C` closes any popup already on the host,
# and the chained `display-popup` opens the picker. Running both in one command
# queue makes tmux repaint once, so there is no flash of the underlying session
# between closing the old popup and showing the picker. (The previous approach
# detached the popup client and polled with sleeps, which left a visible gap.)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefixes_re="^($(provider_prefixes_regex))"
read -r w h < <(popup_dims)

# A client NOT attached to a managed (provider-prefixed) session — the outer
# client that should host the picker popup.
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v re="$prefixes_re" '$2 !~ re { print $1; exit }'
}

host="$(host_client)"
tmux set-option -g @ai_parent "$host"

# Close any popup already open on the host, then open the picker — one command
# queue, one repaint. When invoked from a normal pane the -C is a harmless no-op.
if [ -n "$host" ]; then
  tmux display-popup -C -c "$host" \
    \; display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -C \
    \; display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
