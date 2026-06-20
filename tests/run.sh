#!/usr/bin/env bash
# Self-contained unit tests for the pure helpers in scripts/helpers.sh.
# No external dependencies (no bats): tmux is stubbed so behaviour is
# deterministic. Run:  ./tests/run.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- tmux stub -------------------------------------------------------------
# Reads option values from TMUX_OPTS; everything else is a no-op returning
# non-zero so defaults kick in. Tests populate TMUX_OPTS.
declare -A TMUX_OPTS=()
tmux() {
  if [ "${1:-}" = show-option ]; then
    printf '%s' "${TMUX_OPTS[$3]-}" # show-option -gqv <name>  -> $3 is the name
    return 0
  fi
  return 1
}
export -f tmux

# shellcheck source=../scripts/helpers.sh
. "$ROOT/scripts/helpers.sh"

# --- tiny assertion harness ------------------------------------------------
pass=0 fail=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}

# --- tests -----------------------------------------------------------------
# Default provider list is just claude (opt-in to more via @claude_providers).
check 'default providers' 'claude:claude:Claude' "$(get_providers)"
check 'default prefixes_regex' 'claude-' "$(provider_prefixes_regex)"

# provider_prefix / provider_of_session round-trip
check 'provider_prefix claude' 'claude-' "$(provider_prefix claude)"
check 'provider_of_session claude' 'claude' "$(provider_of_session claude-ab12cd34)"
check 'provider_of_session opencode' 'opencode' "$(provider_of_session opencode-99887766)"

# Custom provider list
TMUX_OPTS=([@claude_providers]='claude:claude:Claude codex:codex:Codex opencode:opencode:OpenCode')
check 'custom prefixes_regex' 'claude-|codex-|opencode-' "$(provider_prefixes_regex)"
check 'label codex' 'Codex' "$(provider_label codex)"
check 'label unknown -> key' 'gemini' "$(provider_label gemini)"

# provider_command resolution order
check 'cmd from list' 'opencode' "$(provider_command opencode)"
check 'cmd unknown -> key' 'gemini' "$(provider_command gemini)"

TMUX_OPTS[@claude_command]='claude --resume'
check 'cmd @claude_command (claude only)' 'claude --resume' "$(provider_command claude)"
check 'cmd override does not leak to codex' 'codex' "$(provider_command codex)"

TMUX_OPTS[@claude_cmd_codex]='codex --model o1'
check 'cmd per-provider with flags' 'codex --model o1' "$(provider_command codex)"
TMUX_OPTS[@claude_cmd_claude]='claude --dangerously-skip-permissions'
check 'cmd per-provider beats @claude_command' 'claude --dangerously-skip-permissions' "$(provider_command claude)"

# Label/command default when the entry omits them
TMUX_OPTS=([@claude_providers]='gemini')
check 'bare entry label -> key' 'gemini' "$(provider_label gemini)"
check 'bare entry command -> key' 'gemini' "$(provider_command gemini)"

# session_hash: stable 8-char, deterministic
h1="$(session_hash /home/me/project)"
h2="$(session_hash /home/me/project)"
check 'session_hash length 8' '8' "${#h1}"
check 'session_hash deterministic' "$h1" "$h2"

# --- summary ---------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
