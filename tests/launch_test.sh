#!/usr/bin/env bash
# Regression coverage for Codex command construction and tmux session metadata.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_BIN="$ROOT/tests/fixtures/launch-bin"

# Keep persistent-launch state isolated so this test never affects the user's
# real Codex session markers.
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-launch-test.XXXXXX")"
LOG="$TEST_ROOT/tmux.log"
STATE_ROOT="$TEST_ROOT/state"
touch "$LOG"
trap 'rm -rf "$TEST_ROOT"' EXIT

# Launch against an existing directory while the fixture captures tmux calls.
TMUX_TEST_LOG="$LOG" \
  XDG_STATE_HOME="$STATE_ROOT" \
  PATH="$FIXTURE_BIN:/usr/bin:/bin" \
  "$ROOT/scripts/launch.sh" "$ROOT" '@7'

new_session="$(awk -F'\t' '$1 == "new-session" { print }' "$LOG")"
session_name="$(printf '%s\n' "$new_session" | cut -f4)"
launch_command="$(printf '%s\n' "$new_session" | cut -f7)"

# The title override must remain one shell argument within tmux's shell command,
# and user-supplied Codex arguments must follow it so they can override defaults.
expected_command='/usr/local/bin/codex -c '\''tui.terminal_title=["status","project"]'\'' --search'
if [ "$launch_command" != "$expected_command" ]; then
  printf 'unexpected Codex launch command\nexpected: %s\nactual:   %s\n' \
    "$expected_command" "$launch_command" >&2
  exit 1
fi

# Completing a first managed launch records that later tmux sessions should
# restore the saved Codex conversation for this directory.
resume_marker="$STATE_ROOT/tmux-codex-session-manager/${session_name#codex-}"
if [ ! -f "$resume_marker" ]; then
  printf 'missing persisted resume marker: %s\n' "$resume_marker" >&2
  exit 1
fi

case "$session_name" in
codex-????????) ;;
*)
  printf 'unexpected managed session name: %s\n' "$session_name" >&2
  exit 1
  ;;
esac

# Ownership and origin metadata must target the same managed session.
if ! awk -F'\t' -v session="$session_name" '
  $1 == "set-option" && $2 == "-t" && $3 == session && $4 == "@codex_managed" && $5 == "1" { found = 1 }
  END { exit !found }
' "$LOG"; then
  printf 'missing explicit @codex_managed ownership marker\n' >&2
  exit 1
fi

if ! awk -F'\t' -v session="$session_name" '
  $1 == "set-option" && $2 == "-t" && $3 == session && $4 == "@codex_origin" && $5 == "@7" { found = 1 }
  END { exit !found }
' "$LOG"; then
  printf 'missing @codex_origin metadata\n' >&2
  exit 1
fi

if ! awk -F'\t' -v session="$session_name" '
  $1 == "display-popup" && $2 == "-w" && $3 == "90%" && $4 == "-h" && $5 == "90%" &&
    $6 == "-E" && $7 == "tmux attach-session -t '\''" session "'\''" { found = 1 }
  END { exit !found }
' "$LOG"; then
  printf 'popup did not attach to the managed Codex session\n' >&2
  exit 1
fi

# Simulate the managed tmux session ending, then verify that reopening the same
# project uses Codex's cwd-scoped persisted-session command.
: >"$LOG"
TMUX_TEST_LOG="$LOG" \
  XDG_STATE_HOME="$STATE_ROOT" \
  PATH="$FIXTURE_BIN:/usr/bin:/bin" \
  "$ROOT/scripts/launch.sh" "$ROOT" '@8'

resumed_command="$(awk -F'\t' '$1 == "new-session" { print $7 }' "$LOG")"
expected_resumed_command='/usr/local/bin/codex -c '\''tui.terminal_title=["status","project"]'\'' resume --last --search'
if [ "$resumed_command" != "$expected_resumed_command" ]; then
  printf 'unexpected Codex resume command\nexpected: %s\nactual:   %s\n' \
    "$expected_resumed_command" "$resumed_command" >&2
  exit 1
fi

# The documented opt-out must ignore an existing marker and launch a new chat.
: >"$LOG"
TMUX_TEST_LOG="$LOG" \
  TMUX_TEST_RESUME='off' \
  XDG_STATE_HOME="$STATE_ROOT" \
  PATH="$FIXTURE_BIN:/usr/bin:/bin" \
  "$ROOT/scripts/launch.sh" "$ROOT" '@9'

fresh_command="$(awk -F'\t' '$1 == "new-session" { print $7 }' "$LOG")"
if [ "$fresh_command" != "$expected_command" ]; then
  printf 'resume opt-out did not launch a fresh Codex session\nexpected: %s\nactual:   %s\n' \
    "$expected_command" "$fresh_command" >&2
  exit 1
fi

printf 'launch_test: ok\n'
