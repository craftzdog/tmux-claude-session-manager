#!/usr/bin/env bash
# Emit one picker row per running Codex process that lives in a tmux pane.
#
# Codex publishes its runtime state in the pane title. Managed sessions force
# the supported status/project title fields, while loose sessions use whatever
# their Codex configuration provides.
#
# Identity is the native Codex process. Joining pid -> tty -> pane lets multiple
# agents in one project each get their own picker row.
#
#   Row: rank \t pane_id \t pid \t kind \t icon \t age \t loc \t path
#   rank/pane_id/pid/kind are hidden from the display via fzf's --with-nth.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

# Optional rollout enrichment maps every native Codex PID to the latest write
# among its open main/subagent transcripts. No transcript content is read.
rollouts="$(codex_rollout_records)"
mtimes="$(printf '%s\n' "$rollouts" | while IFS=$'\t' read -r tag pid rollout; do
  [ "$tag" = R ] && [ -n "$pid" ] && [ -n "$rollout" ] || continue
  printf 'M\t%s\t%s\n' "$pid" "$(file_mtime "$rollout")"
done)"

# Three tagged streams are joined in one awk program: native process -> tty,
# tty -> tmux pane, and process -> latest rollout activity.
{
  ps -Ao pid=,tty=,comm= 2>/dev/null | awk '
    {
      count = split($3, path, "/")
      if (path[count] == "codex") print "P\t" $1 "\t" $2
    }
  '
  tmux list-panes -a -F $'T\t#{pane_tty}\t#{pane_id}\t#{session_name}\t#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_path}\t#{@codex_managed}\t#{pane_title}' 2>/dev/null
  printf '%s\n' "$mtimes"
} | awk -F'\t' -v now="$(date +%s)" -v home="$HOME" '
  $1 == "P" { tty_of[$2] = $3; next }
  $1 == "T" {
    sub(/^\/dev\//, "", $2)
    pane[$2] = $3
    sess[$2] = $4
    loc[$2] = $5
    cwd[$2] = $6
    managed[$2] = $7
    title[$2] = $8
    next
  }
  $1 == "M" {
    if ($3 > seen_at[$2]) seen_at[$2] = $3
    next
  }
  END {
    for (pid in tty_of) {
      tty = tty_of[pid]
      if (tty == "" || !(tty in pane)) continue

      # Codex uses an explicit attention label while waiting and a braille
      # spinner while a turn is running. A plain project title is idle.
      if (title[tty] ~ /Action Required/) {
        icon = "\033[33m●\033[0m waiting"
        rank = 0
      } else if (title[tty] ~ /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/ || title[tty] ~ /^Working([ |]|$)/) {
        icon = "\033[31m●\033[0m working"
        rank = 3
      } else {
        icon = "\033[32m●\033[0m idle   "
        rank = 1
      }

      if (seen_at[pid] != "") {
        minutes = int((now - seen_at[pid]) / 60)
        if (minutes < 0) minutes = 0
        age = minutes "m"
      } else {
        age = "-"
      }

      kind = (managed[tty] == "1") ? "dedicated" : "loose"
      path = cwd[tty]
      if (index(path, home) == 1) path = "~" substr(path, length(home) + 1)

      printf "%s\t%s\t%s\t%s\t%s\t%5s\t%s\t%s\n",
        rank, pane[tty], pid, kind, icon, age, loc[tty], path
    }
  }
' | sort -t$'\t' -k1,1n -k6,6n
# Needs-attention and idle agents float above working ones; each group then
# shows the most recently active agents first.
