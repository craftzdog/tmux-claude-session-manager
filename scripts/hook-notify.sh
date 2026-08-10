#!/usr/bin/env bash
# Claude Code hook handler: plays a sound the moment a session starts
# waiting on you, and a different one when a session finishes while you're
# not looking at it.
#
# Unlike notify.sh, this is not a persistent loop — Claude Code invokes it
# once per real transition (Notification when it needs input, Stop when a
# turn ends), via hooks registered by install-notify-hooks.sh. There is
# nothing to poll and no prev-state to diff against, since Claude Code only
# fires these events on the transitions themselves.
#
# Usage: hook-notify.sh waiting|done   (set as the hook command's argument)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

# Claude Code writes event JSON to stdin; this handler doesn't need any of
# it (the transition kind arrives as $1), but stdin must still be drained.
cat >/dev/null

kind="${1:-}"

[ "$(get_tmux_option @claude_notify_sound 'on')" = "on" ] || exit 0

play_sound() {
  local file="$1"
  [ -f "$file" ] || return 0
  if command -v afplay >/dev/null 2>&1; then
    afplay "$file" >/dev/null 2>&1
  elif command -v paplay >/dev/null 2>&1; then
    paplay "$file" >/dev/null 2>&1
  elif command -v ffplay >/dev/null 2>&1; then
    ffplay -nodisp -autoexit -loglevel quiet "$file" >/dev/null 2>&1
  fi
}

# True when $TMUX_PANE is the active pane of the active window of a session
# an attached client is looking at. $TMUX_PANE is set by tmux in the shell
# that launched `claude` and is inherited down to this hook process, so this
# targets the exact pane directly — no pid/tty/pane join required.
pane_onscreen() {
  [ -n "${TMUX_PANE:-}" ] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  local active window_active attached
  IFS=$'\t' read -r active window_active attached < <(
    tmux display-message -p -t "$TMUX_PANE" $'#{pane_active}\t#{window_active}\t#{session_attached}' 2>/dev/null
  )
  [ "$active" = "1" ] && [ "$window_active" = "1" ] && [ "${attached:-0}" -gt 0 ]
}

case "$kind" in
waiting)
  play_sound "$(get_tmux_option @claude_notify_attention_sound '/System/Library/Sounds/Ping.aiff')"
  ;;
done)
  pane_onscreen || play_sound "$(get_tmux_option @claude_notify_done_sound '/System/Library/Sounds/Glass.aiff')"
  ;;
esac
