#!/usr/bin/env bash
# Interactive picker for running Claude agents.
#
#   picker.sh           fzf picker; on enter, jumps to the chosen agent.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
#
# Rows come from agents.sh, which pairs each running Claude with the tmux pane it
# occupies. Four kinds of row, dispatched on field 7:
#   dedicated  a Claude in a `claude-*` session this plugin launched — resumed in
#              the popup, over the window it was launched from.
#   loose      a Claude running in any other pane — focused in place.
#   bg         the aggregate background-agent row — replaces this picker with the
#              `claude agents` view, in the same popup.
#   note       informational only; selecting it does nothing.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ "${1:-}" = '--list' ] && exec "$DIR/agents.sh"

for tool in fzf jq claude; do
  command -v "$tool" >/dev/null 2>&1 || {
    tmux display-message "tmux-claude-session-manager: $tool is required for the picker"
    exit 0
  }
done

self="$DIR/picker.sh"
export FZF_DEFAULT_OPTS=''
export CLAUDE_PICKER="$self"

# Arbitrary user fzf options (e.g. custom --bind or --preview-window)
extra_opts=()
fzf_options="$(get_tmux_option @claude_fzf_options '')"
[ -n "$fzf_options" ] && eval "extra_opts=($fzf_options)"

# ctrl-x kills the Claude process itself: a dedicated session dies with its last
# window, while a loose pane keeps the shell that hosted it. The reload waits a
# beat so the supervisor has dropped the agent from `claude agents --json`.
#
# ctrl-g is a shortcut to the same place enter takes you on the background row —
# worth its own key because that row moves: it pins to the top only while an agent
# is blocked, and sits at the bottom the rest of the time.
#
# ctrl-g comes back through --expect rather than a become()/execute() binding:
# fzf's stdout is this command substitution, so anything launched from inside the
# binding would render into $out instead of onto the popup. Letting fzf exit first
# puts the terminal back in this script's hands.
out=$("$DIR/agents.sh" | fzf --ansi --delimiter='\t' --with-nth=8 \
  --reverse --cycle --expect=ctrl-g \
  --header='Claude agents · enter: jump · ctrl-g: background agents · ctrl-x: kill' \
  --preview="$DIR/preview.sh {7} {5} {6}" --preview-window='up,70%,follow' \
  --bind="ctrl-x:execute-silent($DIR/kill.sh {7} {6})+reload(sleep 0.3; $self --list)" \
  ${extra_opts[@]+"${extra_opts[@]}"})

# --expect puts the pressed key on line 1 (empty for a plain enter) and the chosen
# row on line 2.
key=$(printf '%s\n' "$out" | sed -n 1p)
sel=$(printf '%s\n' "$out" | sed -n 2p)

# Replaces the picker inside the popup it already owns, so there is no second
# display-popup racing the first one's teardown (the dance list.sh has to do).
[ "$key" = 'ctrl-g' ] && exec claude agents

[ -z "$sel" ] && exit 0
pane=$(printf '%s' "$sel" | cut -f5)
kind=$(printf '%s' "$sel" | cut -f7)

[ "$kind" = bg ] && exec claude agents
[ "$kind" = note ] && exit 0

parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)

if [ "$kind" = loose ]; then
  # Focus the pane in place on the outer client. This popup closes on its own
  # when the script exits.
  if [ -n "$parent" ]; then
    tmux switch-client -c "$parent" -t "$session" 2>/dev/null
  else
    tmux switch-client -t "$session" 2>/dev/null
  fi
  tmux select-window -t "$pane" 2>/dev/null
  tmux select-pane -t "$pane" 2>/dev/null
  exit 0
fi

# Move the parent client to the window the session was launched from (best-effort),
# focus the chosen Claude's own window inside that session, then resume it in THIS
# popup over the top. Falls back to resuming over the current window when
# origin/parent are unknown.
origin=$(tmux show-options -qv -t "$session" @claude_origin 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux select-window -t "$pane" 2>/dev/null
tmux select-pane -t "$pane" 2>/dev/null
tmux attach-session -t "$session"
