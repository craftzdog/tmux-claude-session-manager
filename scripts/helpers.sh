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

# ---------------------------------------------------------------------------
# AI providers
#
# A provider is one launchable AI CLI (Claude, Codex, OpenCode, ...). The set is
# configurable via the @claude_providers tmux option as a space-separated list
# of  key:command:Label  entries:
#
#   set -g @claude_providers 'claude:claude:Claude codex:codex:Codex'
#
# - key     identifies the provider and forms its session prefix ("claude-").
# - command is what runs inside the session (defaults to key when omitted).
# - Label   is shown in the launch menu and picker (defaults to key).
# ---------------------------------------------------------------------------
default_providers='claude:claude:Claude codex:codex:Codex opencode:opencode:OpenCode'

get_providers() {
  get_tmux_option @claude_providers "$default_providers"
}

# provider_prefix <key> -> session-name prefix, e.g. "claude-"
provider_prefix() { printf '%s-' "$1"; }

# provider_command <key> -> command to run for that provider.
# Honors @claude_command as an override for the claude provider (back-compat).
provider_command() {
  local want="$1" entry key command
  if [ "$want" = claude ]; then
    local override
    override="$(tmux show-option -gqv @claude_command 2>/dev/null)"
    [ -n "$override" ] && { printf '%s' "$override"; return; }
  fi
  for entry in $(get_providers); do
    IFS=: read -r key command _ <<<"$entry"
    [ "$key" = "$want" ] && { printf '%s' "${command:-$key}"; return; }
  done
  printf '%s' "$want"
}

# provider_of_session <session-name> -> provider key (text before the hash).
# Session names are "<key>-<8charhash>" and keys contain no dash.
provider_of_session() { printf '%s' "${1%-*}"; }

# provider_label <key> -> human label from the providers list (defaults to key).
provider_label() {
  local want="$1" entry key label
  for entry in $(get_providers); do
    IFS=: read -r key _ label <<<"$entry"
    [ "$key" = "$want" ] && { printf '%s' "${label:-$key}"; return; }
  done
  printf '%s' "$want"
}

# provider_prefixes_regex -> alternation of every provider prefix, e.g.
# "claude-|codex-|opencode-" for anchoring grep/awk matches.
provider_prefixes_regex() {
  local entry key out=''
  for entry in $(get_providers); do
    IFS=: read -r key _ _ <<<"$entry"
    out="${out}${out:+|}$(provider_prefix "$key")"
  done
  printf '%s' "$out"
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
  printf '%s' "${out%% *}" | cut -c1-8
}
