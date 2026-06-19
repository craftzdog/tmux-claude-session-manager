#!/usr/bin/env bash
# Self-contained unit tests for the pure helpers in scripts/helpers.sh.
# No external dependencies (no bats): tmux is stubbed so behaviour is
# deterministic. Run:  ./tests/run.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- tmux stub -------------------------------------------------------------
# Reads option values from the TMUX_OPTS associative array; everything else is
# a no-op returning non-zero so defaults kick in. Tests populate TMUX_OPTS.
declare -A TMUX_OPTS=()
tmux() {
  if [ "${1:-}" = show-option ]; then
    # show-option -gqv <name>  -> $3 is the name
    printf '%s' "${TMUX_OPTS[$3]-}"
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
# provider_prefix / provider_of_session round-trip
check 'provider_prefix claude' 'claude-' "$(provider_prefix claude)"
check 'provider_of_session claude' 'claude' "$(provider_of_session claude-ab12cd34)"
check 'provider_of_session opencode' 'opencode' "$(provider_of_session opencode-99887766)"

# provider_prefixes_regex from defaults
check 'prefixes_regex defaults' 'claude-|codex-|opencode-' "$(provider_prefixes_regex)"

# provider_label from default list
check 'label codex' 'Codex' "$(provider_label codex)"
check 'label unknown -> key' 'gemini' "$(provider_label gemini)"

# provider_command resolution order
TMUX_OPTS=()
check 'cmd from list' 'opencode' "$(provider_command opencode)"
check 'cmd unknown -> key' 'gemini' "$(provider_command gemini)"

TMUX_OPTS[@claude_command]='claude --resume'
check 'cmd legacy override (claude only)' 'claude --resume' "$(provider_command claude)"
check 'cmd legacy does not leak to codex' 'codex' "$(provider_command codex)"

TMUX_OPTS[@claude_cmd_codex]='codex --model o1'
check 'cmd per-provider with flags' 'codex --model o1' "$(provider_command codex)"
TMUX_OPTS[@claude_cmd_claude]='claude --dangerously-skip-permissions'
check 'cmd per-provider beats legacy' 'claude --dangerously-skip-permissions' "$(provider_command claude)"

# custom @claude_providers
TMUX_OPTS=([@claude_providers]='claude:claude:Claude gemini:gemini:Gemini')
check 'custom providers regex' 'claude-|gemini-' "$(provider_prefixes_regex)"
check 'custom providers label' 'Gemini' "$(provider_label gemini)"

# popup_dims defaults and overrides
TMUX_OPTS=()
check 'popup_dims defaults' '90% 90%' "$(popup_dims)"
TMUX_OPTS=([@claude_popup_width]='70%' [@claude_popup_height]='80%')
check 'popup_dims overrides' '70% 80%' "$(popup_dims)"

# session_hash: stable 8-char, deterministic
h1="$(session_hash /home/me/project)"
h2="$(session_hash /home/me/project)"
check 'session_hash length 8' '8' "${#h1}"
check 'session_hash deterministic' "$h1" "$h2"

# --- summary ---------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
