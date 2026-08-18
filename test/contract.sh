#!/usr/bin/env bash
# Contract test for tmux-claude-session-manager.
#
# This plugin reads two very different surfaces, and they carry different risk:
#
#   documented  `claude agents --json` — field names and the state/status
#               vocabularies are published in the Claude Code docs (agent-view).
#               Asserted strictly: an unknown value fails, because that is
#               exactly the drift we want to hear about.
#
#   internal    ~/.claude/projects/<slug>/<sessionId>.jsonl and its `ai-title`
#               record. Undocumented, may move without notice. Asserted too, but
#               they only feed the title and age columns, so a break here
#               degrades the display rather than breaking the picker.
#
# Fixture checks need neither tmux nor a running Claude and always run. Live
# checks skip themselves when there is nothing running, so an unattended run at
# 04:00 reports "skipped", never a false alarm.
#
#   ./test/contract.sh          run everything
#   ./test/contract.sh --quiet  print only failures and a one-line summary
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$DIR/scripts/helpers.sh"

quiet=''; [ "${1:-}" = '--quiet' ] && quiet=1
pass=0; fail=0; skip=0

ok()   { pass=$((pass+1)); [ -n "$quiet" ] || printf '  \033[32mok\033[0m    %s\n' "$1"; }
no()   { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
sk()   { skip=$((skip+1)); [ -n "$quiet" ] || printf '  \033[90mskip\033[0m  %s (%s)\n' "$1" "$2"; }
head_() { [ -n "$quiet" ] || printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- documented --
head_ 'Documented: claude agents --json'

agents="$(claude agents --json 2>/dev/null)"
if [ -z "$agents" ] || ! printf '%s' "$agents" | jq -e 'type == "array"' >/dev/null 2>&1; then
  no 'returns a JSON array' 'claude agents --json produced nothing parseable'
  agents='[]'
else
  ok 'returns a JSON array'
fi

n_all=$(printf '%s' "$agents" | jq 'length')
if [ "$n_all" -eq 0 ]; then
  sk 'field and vocabulary checks' 'no live sessions'
else
  # Always-present fields, per the docs table.
  missing=$(printf '%s' "$agents" | jq -r '[.[] | select(has("cwd") and has("kind") and has("startedAt") | not)] | length')
  [ "$missing" = 0 ] && ok 'every entry has cwd, kind, startedAt' \
                     || no 'every entry has cwd, kind, startedAt' "$missing entries missing one"

  bad=$(printf '%s' "$agents" | jq -r '[.[].kind] | unique - ["interactive","background"] | join(", ")')
  [ -z "$bad" ] && ok 'kind is interactive|background' || no 'kind is interactive|background' "unknown: $bad"

  # The vocabularies agents.sh branches on. A new value here means the picker is
  # silently rendering it as the grey "?" row, or miscounting the background row.
  bad=$(printf '%s' "$agents" | jq -r '[.[] | .state // empty] | unique - ["working","blocked","done","failed","stopped"] | join(", ")')
  [ -z "$bad" ] && ok 'background state in documented set' || no 'background state in documented set' "undocumented: $bad"

  bad=$(printf '%s' "$agents" | jq -r '[.[] | .status // empty] | unique - ["idle","busy","waiting"] | join(", ")')
  [ -z "$bad" ] && ok 'interactive status in known set' || no 'interactive status in known set' "unknown: $bad"

  # Documented: waitingFor is present whenever status is waiting.
  n_wait=$(printf '%s' "$agents" | jq '[.[] | select(.status == "waiting")] | length')
  if [ "$n_wait" -eq 0 ]; then
    sk 'waiting entries carry waitingFor' 'nothing waiting'
  else
    bad=$(printf '%s' "$agents" | jq '[.[] | select(.status == "waiting" and (has("waitingFor") | not))] | length')
    [ "$bad" = 0 ] && ok 'waiting entries carry waitingFor' || no 'waiting entries carry waitingFor' "$bad without it"
  fi

  # Interactive entries must expose a pid — the whole pid -> tty -> pane join
  # depends on it, and background entries deliberately have none.
  bad=$(printf '%s' "$agents" | jq '[.[] | select(.kind == "interactive" and (has("pid") | not))] | length')
  [ "$bad" = 0 ] && ok 'interactive entries expose pid' || no 'interactive entries expose pid' "$bad without pid"
fi

# ----------------------------------------------------------------- internal --
head_ 'Internal: transcript layout and ai-title'

sid=$(printf '%s' "$agents" | jq -r '[.[] | select(.kind == "interactive") | .sessionId] | first // empty')
if [ -z "$sid" ]; then
  sk 'transcript path resolves' 'no interactive session'
  sk 'ai-title parses' 'no interactive session'
else
  f="$(claude_transcript_path "$sid")"
  if [ -n "$f" ] && [ -f "$f" ]; then
    ok 'transcript path resolves'
    if [ -n "$(claude_transcript_title "$f")" ]; then
      ok 'ai-title parses to a non-empty title'
    else
      # Not fatal: the column blanks out, the picker still works.
      no 'ai-title parses to a non-empty title' "no ^{\"type\":\"ai-title\"} record in $(basename "$f")"
    fi
  else
    no 'transcript path resolves' "no transcript found for $sid under \${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/"
  fi
fi

# ------------------------------------------------------------------ fixture --
# Drives rows.awk with synthetic streams, so these run anywhere: no tmux, no
# Claude, no network. This is the half that CI can run.
head_ 'Fixture: row rendering'

run_fixture() {
  awk -F'\t' -v now=1000000 -v bg_attn="$1" -v bg_active="$2" -v projw=24 -v prefix='claude-' \
    -f "$DIR/scripts/rows.awk"
}
fixture_streams() {
  printf 'P\t4242\tpts/99\n'
  printf 'T\t/dev/pts/99\t%%99\twork\twork:9.0\n'
  printf 'M\tSID\t999400\tRework the upload endpoint\n'
  printf 'A\t4242\t%s\tSID\t%s\t%s\n' "$1" "$2" "${3:-}"
}

out=$(fixture_streams waiting /srv/example/docs-site 'permission prompt' | run_fixture 0 0)
row=$(printf '%s' "$out" | head -1)

[ "$(printf '%s' "$row" | awk -F'\t' '{print NF}')" = 8 ] \
  && ok 'row has 8 tab-separated fields' \
  || no 'row has 8 tab-separated fields' "got $(printf '%s' "$row" | awk -F'\t' '{print NF}')"

printf '%s' "$row" | grep -q 'permission prompt' \
  && ok 'waiting row surfaces waitingFor' || no 'waiting row surfaces waitingFor'

[ "$(printf '%s' "$row" | cut -f3)" = 0 ] \
  && ok 'waiting ranks above idle and busy' || no 'waiting ranks above idle and busy'

[ "$(printf '%s' "$row" | cut -f7)" = loose ] \
  && ok 'pane outside the session prefix is loose' || no 'pane outside the session prefix is loose'

# Age rolls up so it cannot overflow the column.
out=$(printf 'P\t1\tpts/99\nT\t/dev/pts/99\t%%99\twork\twork:9.0\nM\tS\t560000\tT\nA\t1\tidle\tS\t/x\t\n' | run_fixture 0 0)
printf '%s' "$out" | head -1 | grep -qE '[0-9]+d ' \
  && ok 'multi-day age renders as days, not minutes' || no 'multi-day age renders as days, not minutes'

# Worktrees fold into their repo group instead of each becoming a project of one.
out=$(fixture_streams idle '/srv/example/monorepo/.claude/worktrees/fix-1' | run_fixture 0 0)
printf '%s' "$out" | head -1 | grep -q 'monorepo/fix-1' \
  && ok 'worktree folds into its repo group' || no 'worktree folds into its repo group'
[ "$(printf '%s' "$out" | head -1 | cut -f2)" = /srv/example/monorepo ] \
  && ok 'worktree sorts under the repo path' || no 'worktree sorts under the repo path'

# Background row: pinned on top when anything needs you, parked at the bottom otherwise.
out=$(fixture_streams idle /x | run_fixture 2 1)
bg=$(printf '%s' "$out" | awk -F'\t' '$7 == "bg"')
[ "$(printf '%s' "$bg" | cut -f1)" = '-1' ] && ok 'bg row pins to top when agents need you' || no 'bg row pins to top when agents need you'
printf '%s' "$bg" | grep -q '2 need you, 1 running' && ok 'bg row reports both counts' || no 'bg row reports both counts'

out=$(fixture_streams idle /x | run_fixture 0 3)
bg=$(printf '%s' "$out" | awk -F'\t' '$7 == "bg"')
[ "$(printf '%s' "$bg" | cut -f1)" = 99 ] && ok 'bg row sinks when nothing needs you' || no 'bg row sinks when nothing needs you'

# A Claude with no tmux pane must be surfaced, never silently dropped.
out=$(printf 'A\t7777\tidle\tS\t/x\t\n' | run_fixture 0 0)
note=$(printf '%s' "$out" | awk -F'\t' '$7 == "note"')
[ -n "$note" ] && ok 'session outside tmux gets a row' || no 'session outside tmux gets a row'
[ "$(printf '%s' "$note" | cut -f6)" = 7777 ] \
  && ok 'outside-tmux row carries its pids for the preview' || no 'outside-tmux row carries its pids for the preview'

# --------------------------------------------------------------- end-to-end --
head_ 'End-to-end: agents.sh against the live machine'

if ! command -v tmux >/dev/null 2>&1 || ! tmux list-panes -a >/dev/null 2>&1; then
  sk 'agents.sh produces well-formed rows' 'no tmux server'
else
  live=$("$DIR/scripts/agents.sh")
  widths=$(printf '%s\n' "$live" | awk -F'\t' 'NF != 8' | wc -l)
  [ "$widths" -eq 0 ] && ok 'every row has 8 fields' || no 'every row has 8 fields' "$widths malformed"

  bad=0
  while IFS= read -r r; do
    case "$(printf '%s' "$r" | cut -f7)" in
      loose | dedicated)
        tmux display-message -p -t "$(printf '%s' "$r" | cut -f5)" '#{session_name}' >/dev/null 2>&1 || bad=$((bad+1)) ;;
    esac
  done <<< "$live"
  [ "$bad" -eq 0 ] && ok 'every pane id resolves to a live pane' || no 'every pane id resolves to a live pane' "$bad dangling"
fi

# ------------------------------------------------------------------ summary --
printf '\n%s\n' "$(printf '%d passed, %d failed, %d skipped' "$pass" "$fail" "$skip")"
[ "$fail" -eq 0 ]
