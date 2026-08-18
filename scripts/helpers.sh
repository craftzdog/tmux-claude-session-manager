#!/usr/bin/env bash
# Shared helpers for tmux-claude-session-manager.

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

# reverse_lines <path>
# Stream a file last line first. GNU coreutils ships `tac`, BSD/macOS ships
# `tail -r`; neither exists on the other, so the fallback is unambiguous.
reverse_lines() {
  tac "$1" 2>/dev/null || tail -r "$1" 2>/dev/null
}

# claude_transcript_path <session-id>
# Path to that session's transcript, or empty when it cannot be found.
#
# Found by glob so we never have to reproduce Claude's cwd -> project-slug
# encoding. The layout is an internal Claude Code detail and may move; every
# caller degrades to a blank column rather than failing.
claude_transcript_path() {
  local base f
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  for f in "$base"/projects/*/"$1".jsonl; do
    [ -f "$f" ] && {
      printf '%s' "$f"
      return
    }
  done
}

# claude_transcript_mtime <transcript-path>
# Epoch seconds of the last write to a session's transcript — i.e. when the agent
# last did anything. `claude agents --json` reports only `startedAt`, never a
# last-activity time, so the transcript's mtime stands in for it.
claude_transcript_mtime() {
  [ -n "$1" ] && file_mtime "$1"
}

# claude_transcript_title <transcript-path>
# The session's current AI-generated title. Claude Code appends an `ai-title`
# record whenever its sense of the conversation's topic changes, so the last one
# wins — hence reading the file backwards and stopping at the first hit.
#
# Parsed with jq rather than a regex because a title may legitimately contain a
# quote, which a "[^"]*" match would truncate mid-word. Tabs and newlines are
# squeezed out because these rows are TSV.
#
# The match is anchored: every transcript record is one JSON object per line, and
# an unanchored search would also hit message records that merely quote the string
# — a session whose own transcript discusses ai-title would shadow its real title
# with a record that has no .aiTitle, blanking the column.
claude_transcript_title() {
  [ -n "$1" ] || return
  reverse_lines "$1" |
    grep -m1 '^{"type":"ai-title"' |
    jq -r '.aiTitle // empty' 2>/dev/null |
    tr '\t\n' '  ' |
    sed 's/[[:space:]]*$//'
}
