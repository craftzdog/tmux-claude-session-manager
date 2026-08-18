#!/usr/bin/env bash
# Emit the picker rows: one per running Claude that lives in a tmux pane, plus
# aggregate rows for things that exist but cannot be jumped to.
#
# Claude self-reports its status: each session writes its own state to disk and a
# supervisor daemon aggregates it, which `claude agents --json` publishes. So this
# needs no Claude Code hooks, and no `pane_current_command` scan — on macOS a pane
# reports its parent shell there, never the `claude` child running inside it.
#
# Identity is the Claude process, not the tmux session. Joining pid -> tty -> pane
# is what lets several Claudes in one project (same cwd, same session, different
# windows) each get a row of their own.
#
#   Row: grp \t proj \t rank \t agemin \t pane_id \t pid \t kind \t display
#         \___________ sort + dispatch keys, hidden ___________/ \_ --with-nth=8 _/
#
# The visible half is one pre-padded field rather than several, because fzf joins
# --with-nth fields back together with the delimiter — a tab here — and tab stops
# would jitter the columns out of alignment as titles change length.
#
# Rows cluster by project, and a project is ordered by its most urgent member, so
# grouping never buries something that needs you. `kind` tells picker.sh how to
# act on a row: loose/dedicated jump to a pane, bg opens the background-agent
# view, note is inert.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

agents="$(claude agents --json 2>/dev/null)" || exit 0
[ -n "$agents" ] || exit 0

rows="$(printf '%s' "$agents" |
  jq -r '.[] | select(.kind == "interactive")
        | [.pid, .status, .sessionId, .cwd, (.waitingFor // "")] | @tsv' 2>/dev/null)"

# Background agents carry `id` and `state`, never `pid`/`status` like interactive
# ones — different keys, and non-overlapping vocabularies (working/blocked/done/
# failed/stopped vs idle/busy/waiting). With no pid there is no tty and no pane,
# so they can never be rows
# you jump to; they collapse into one row that opens `claude agents` instead.
#
# Counted off the same JSON. Without --all it already omits completed sessions, so
# what is left is live. The documented states are working|blocked|done|failed|
# stopped; `blocked` and `failed` are the two that want a human, and anything else
# still listed is running. Split by naming the attention states rather than the
# running ones, so a state added later shows up as running instead of silently
# inflating the count that pins this row to the top.
bg_attn="$(printf '%s' "$agents" |
  jq '[.[] | select(.kind == "background" and (.state == "blocked" or .state == "failed"))] | length' 2>/dev/null)"
bg_active="$(printf '%s' "$agents" |
  jq '[.[] | select(.kind == "background" and .state != "blocked" and .state != "failed")] | length' 2>/dev/null)"

# Resolved out here because awk can read neither an mtime nor a second file.
# One glob per session feeds both columns.
meta=''
if [ -n "$rows" ]; then
  meta="$(printf '%s\n' "$rows" | cut -f3 | while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    f="$(claude_transcript_path "$sid")"
    printf 'M\t%s\t%s\t%s\n' \
      "$sid" "$(claude_transcript_mtime "$f")" "$(claude_transcript_title "$f")"
  done)"
fi

# Four tagged streams into one awk: pid->tty, tty->pane, session->activity+title,
# and the agents themselves. Total cost is 3 subprocesses regardless of how many
# sessions or panes exist.
{
  ps -Ao pid=,tty= 2>/dev/null | awk '{ print "P\t" $1 "\t" $2 }'
  tmux list-panes -a -F $'T\t#{pane_tty}\t#{pane_id}\t#{session_name}\t#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null
  [ -n "$meta" ] && printf '%s\n' "$meta"
  [ -n "$rows" ] && printf '%s\n' "$rows" | sed $'s/^/A\t/'
} | awk -F'\t' -v now="$(date +%s)" \
  -v bg_attn="${bg_attn:-0}" -v bg_active="${bg_active:-0}" \
  -v projw="$(get_tmux_option @claude_project_width '24')" \
  -v prefix="$(get_tmux_option @claude_session_prefix 'claude-')" \
  -f "$DIR/rows.awk" | sort -t$'\t' -k1,1n -k2,2 -k3,3n -k4,4n
# Group by most-urgent-member first, then project name to keep a group contiguous,
# then rank and age within the group.
