#!/usr/bin/env bash
# Shared helpers for tmux-claude-session-manager.

# get_opt <suffix> <default>
# Reads the user-facing option @ai_<suffix>, falling back to the deprecated
# @claude_<suffix> alias, then <default>. All user-facing options go through this
# so the plugin's @ai_* namespace is canonical while existing @claude_* configs
# keep working unchanged.
get_opt() {
  local value
  value="$(tmux show-option -gqv "@ai_$1" 2>/dev/null)"
  [ -n "$value" ] && { printf '%s' "$value"; return; }
  value="$(tmux show-option -gqv "@claude_$1" 2>/dev/null)"
  [ -n "$value" ] && { printf '%s' "$value"; return; }
  printf '%s' "$2"
}

# popup_dims -> "<width> <height>" for display-popup, from @ai_popup_width /
# @ai_popup_height (defaults 90%/90%). Read with: read -r w h < <(popup_dims)
popup_dims() {
  printf '%s %s' \
    "$(get_opt popup_width '90%')" \
    "$(get_opt popup_height '90%')"
}

# ---------------------------------------------------------------------------
# AI providers
#
# A provider is one launchable AI CLI (Claude, Codex, OpenCode, ...). The set is
# configurable via the @ai_providers tmux option as a space-separated list
# of  key:command:Label  entries:
#
#   set -g @ai_providers 'claude:claude:Claude codex:codex:Codex'
#
# - key     identifies the provider and forms its session prefix ("claude-").
# - command is what runs inside the session (defaults to key when omitted).
# - Label   is shown in the launch menu and picker (defaults to key).
# ---------------------------------------------------------------------------
default_providers='claude:claude:Claude codex:codex:Codex opencode:opencode:OpenCode'

get_providers() {
  get_opt providers "$default_providers"
}

# provider_prefix <key> -> session-name prefix, e.g. "claude-"
provider_prefix() { printf '%s-' "$1"; }

# provider_command <key> -> command to run for that provider.
# Resolution order (first non-empty wins):
#   1. @ai_cmd_<key>  per-provider option — may contain spaces/flags, e.g.
#                     set -g @ai_cmd_codex 'codex --model o1'
#   2. @ai_command    override, claude provider only (legacy @claude_command alias)
#   3. the command field of the @ai_providers entry (no spaces — see header)
#   4. the key itself
# (1) and (2) also accept the deprecated @claude_* spelling via get_opt. The
# per-provider option exists because @ai_providers is space-delimited and
# therefore cannot carry a command with arguments; this option can.
provider_command() {
  local want="$1" entry key command override
  override="$(get_opt "cmd_${want}" '')"
  [ -n "$override" ] && { printf '%s' "$override"; return; }
  if [ "$want" = claude ]; then
    override="$(get_opt command '')"
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
