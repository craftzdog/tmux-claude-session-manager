#!/usr/bin/env bash
# Shared helpers for tmux-codex-session-manager.

# get_tmux_option <option-name> <default>
# Echoes the global tmux option value, or the default when unset/empty.
get_tmux_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

# session_hash <string>
# Short, stable, portable 8-char hash for deriving a session name from a path.
# Prefers md5sum (Linux), falls back to md5 (macOS) then shasum. The trailing
# newline matches the conventional `echo "$path" | md5sum` scheme, so it stays
# compatible with sessions created that way.
session_hash() {
  local out
  if command -v md5sum >/dev/null 2>&1; then
    out="$(printf '%s\n' "$1" | md5sum)"
  elif command -v md5 >/dev/null 2>&1; then
    out="$(printf '%s\n' "$1" | md5 -q)"
  else
    out="$(printf '%s\n' "$1" | shasum)"
  fi
  out="${out%% *}"
  printf '%s' "${out:0:8}"
}

# file_mtime <path>
# Epoch seconds of a file's last modification. GNU stat (Linux) is tried first,
# then BSD (macOS); each rejects the other's flag, so the fallback is unambiguous.
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# codex_rollout_records
# Emits R<TAB>pid<TAB>path for rollout files held open by Codex processes.
# lsof is optional: process and status discovery still work without activity age.
codex_rollout_records() {
  local base line pid
  command -v lsof >/dev/null 2>&1 || return 0

  base="${CODEX_HOME:-$HOME/.codex}/sessions/"
  pid=''
  lsof -Fn -c codex 2>/dev/null | while IFS= read -r line; do
    case "$line" in
    p[0-9]*) pid="${line#p}" ;;
    n"$base"*.jsonl)
      [ -n "$pid" ] && printf 'R\t%s\t%s\n' "$pid" "${line#n}"
      ;;
    esac
  done
}
