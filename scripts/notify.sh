#!/usr/bin/env bash
# Background watcher: plays a sound the moment a Claude session starts
# waiting on you, and a different one when a session finishes while you're
# not looking at it.
#
# Unlike agents.sh (computed on demand when the picker opens), this runs as
# a long-lived loop so it can react to state *transitions* between picker
# opens. One instance per machine: a pidfile keeps a config reload
# (`prefix + r`, which re-sources this plugin) from stacking up duplicate
# loops. The loop exits on its own once the tmux server it was launched
# under is gone.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ "$(get_tmux_option @claude_notify_sound 'on')" = "on" ] || exit 0

interval="$(get_tmux_option @claude_notify_interval '2')"
attention_sound="$(get_tmux_option @claude_notify_attention_sound '/System/Library/Sounds/Ping.aiff')"
done_sound="$(get_tmux_option @claude_notify_done_sound '/System/Library/Sounds/Glass.aiff')"

run_dir="${TMPDIR:-/tmp}"
pid_file="$run_dir/tmux-claude-session-manager-notify.pid"
state_file="$run_dir/tmux-claude-session-manager-notify.state"

# Singleton: bail out if a live instance already owns the pidfile. Racy in
# theory (two instances could both pass the check before either writes), but
# both invocations here always come from the same serial tmux config load,
# so in practice this never fires concurrently.
if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi
echo $$ >"$pid_file"
trap 'rm -f "$pid_file"' EXIT

play_sound() {
  local file="$1"
  [ -f "$file" ] || return 0
  if command -v afplay >/dev/null 2>&1; then
    afplay "$file" >/dev/null 2>&1 &
  elif command -v paplay >/dev/null 2>&1; then
    paplay "$file" >/dev/null 2>&1 &
  elif command -v ffplay >/dev/null 2>&1; then
    ffplay -nodisp -autoexit -loglevel quiet "$file" >/dev/null 2>&1 &
  fi
}

: >"$state_file"

while :; do
  # The loop's own lifetime is tied to this check, not to any tmux hook:
  # once the server that launched us is gone, stop polling for it.
  tmux list-sessions >/dev/null 2>&1 || break

  agents="$(claude agents --json 2>/dev/null)"
  rows=""
  if [ -n "$agents" ]; then
    rows="$(printf '%s' "$agents" |
      jq -r '.[] | select(.kind == "interactive") | [.pid, .status] | @tsv' 2>/dev/null)"
  fi

  snapshot=""
  if [ -n "$rows" ]; then
    # Same pid -> tty -> pane join as agents.sh, plus whether that pane is
    # the one currently on screen for an attached client (active pane, of
    # the active window, of a session someone is attached to).
    snapshot="$({
      ps -Ao pid=,tty= 2>/dev/null | awk '{ print "P\t" $1 "\t" $2 }'
      tmux list-panes -a -F $'T\t#{pane_tty}\t#{pane_active}\t#{window_active}\t#{session_attached}' 2>/dev/null
      printf '%s\n' "$rows" | sed $'s/^/A\t/'
    } | awk -F'\t' '
      $1 == "P" { tty_of[$2] = $3; next }
      $1 == "T" {
        sub(/^\/dev\//, "", $2)
        onscreen[$2] = ($3 == 1 && $4 == 1 && $5 > 0) ? 1 : 0
        next
      }
      $1 == "A" {
        tty = tty_of[$2]
        if (tty == "" || !(tty in onscreen)) next
        printf "%s\t%s\t%s\n", $2, $3, onscreen[tty]
      }
    ')"
  fi

  while IFS=$'\t' read -r pid status onscreen; do
    [ -n "$pid" ] || continue
    prev_status="$(awk -F'\t' -v p="$pid" '$1 == p { print $2; exit }' "$state_file")"

    if [ "$status" = "waiting" ] && [ "$prev_status" != "waiting" ]; then
      play_sound "$attention_sound"
    elif [ "$status" = "idle" ] &&
      { [ "$prev_status" = "busy" ] || [ "$prev_status" = "waiting" ]; } &&
      [ "$onscreen" != "1" ]; then
      play_sound "$done_sound"
    fi
  done <<<"$snapshot"

  printf '%s\n' "$snapshot" >"$state_file"
  sleep "$interval"
done
