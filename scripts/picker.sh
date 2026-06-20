#!/usr/bin/env bash
# Interactive picker for running Claude sessions.
#
#   picker.sh           fzf picker; on enter, switches the parent client to the
#                       chosen session's origin window and resumes it in the popup.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefixes_re="$(provider_prefixes_regex)"

emit_rows() {
  local now s state at path icon rank ago provider
  now=$(date +%s)
  # One tmux call pulls every session's name, state, timestamp and path at once.
  # Session-scoped user options are read inline via #{@ai_state} etc., so we
  # avoid the previous per-session show-options/display-message subprocess fan-out.
  while IFS=$'\t' read -r s state at path; do
    provider=$(provider_label "$(provider_of_session "$s")")
    case "$state" in
      waiting) icon=$'\033[33m●\033[0m waiting' rank=0 ;; # yellow - needs input
      idle)    icon=$'\033[32m●\033[0m idle   ' rank=1 ;; # green  - done, your turn
      working) icon=$'\033[31m●\033[0m working' rank=3 ;; # red    - busy, leave it
      *)       icon=$'\033[90m●\033[0m   ?    ' rank=2 ;; # grey   - unknown (no hook yet)
    esac
    if [ -n "$at" ]; then ago="$(( (now - at) / 60 ))m"; else ago='-'; fi
    # rank \t session \t provider \t icon \t path \t age  (rank/session hidden via --with-nth)
    printf '%s\t%s\t%-9s\t%s\t%s\t%s\n' "$rank" "$s" "$provider" "$icon" "${path/#$HOME/~}" "$ago"
  done < <(tmux list-sessions \
             -F "#{session_name}	#{@ai_state}	#{@ai_state_at}	#{pane_current_path}" \
             2>/dev/null | grep -E "^(${prefixes_re})") |
    sort -n # attention-needed (waiting, idle) float to the top
}

[ "${1:-}" = '--list' ] && { emit_rows; exit 0; }

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-claude-session-manager: fzf is required for the picker"
  exit 0
fi

self="${BASH_SOURCE[0]}"

# Base options shared by every fzf version.
# --height=100% fills the whole popup; it overrides any --height (e.g. 40%) the
# user set in FZF_DEFAULT_OPTS, which would otherwise leave the lower part of the
# popup blank. Command-line opts win over FZF_DEFAULT_OPTS.
fzf_opts=(
  --ansi --delimiter='\t' --with-nth=3,4,5,6
  --reverse --cycle --height=100%
  --preview="tmux capture-pane -ept {2}"
  --preview-window='right,70%,wrap'  # 3/7 split: list 30% · preview 70%
  --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload($self --list)"
)

# Bordered, multi-pane layout (fzf >= 0.53). Each region gets its own labelled
# box — input, results list, preview — mirroring the lazy.nvim help viewer.
# Older fzf lacks these flags, so fall back to a plain header + preview split.
if fzf --help 2>&1 | grep -q -- '--list-border'; then
  fzf_opts+=(
    --style=full
    --input-border   --input-label=' AI sessions '
    --list-border    --list-label=' Results '
    --preview-border --preview-label=' Preview '
    --color='label:bold'
    --pointer='▶'
    --prompt='  '
    --header='enter: jump · ctrl-x: kill'
  )
else
  fzf_opts+=(--header='AI sessions · enter: jump · ctrl-x: kill')
fi

# User escape hatch. @ai_picker_opts is appended last, so it overrides anything
# above (theme, --info, extra binds — even layout flags if the user insists)
# without editing this script. Tokens are space-split, so it suits a list of
# simple flags; values containing spaces are not supported here. The guard keeps
# bash 3.2 (stock macOS) happy, where expanding an empty array under `set -u`
# raises "unbound variable".
extra_opts="$(get_opt picker_opts '')"
if [ -n "$extra_opts" ]; then
  read -ra extra_arr <<<"$extra_opts"
  fzf_opts+=("${extra_arr[@]}")
fi

sel=$(emit_rows | fzf "${fzf_opts[@]}")

[ -z "$sel" ] && exit 0
target=$(printf '%s' "$sel" | cut -f2)

# Move the underlying parent client to the session's origin window (best-effort),
# then resume the session in THIS popup over it. Falls back to resuming over the
# current window when origin/parent are unknown.
origin=$(tmux show-options -qv -t "$target" @ai_origin 2>/dev/null)
parent=$(tmux show-options -gqv @ai_parent 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] && \
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux attach-session -t "$target"
