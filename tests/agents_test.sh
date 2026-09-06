#!/usr/bin/env bash
# Fixture-based regression coverage for process filtering, TTY joins, title
# status parsing, rollout activity, path shortening, and dedicated-session kind.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_BIN="$ROOT/tests/fixtures/bin"

# Keep the command surface deterministic while retaining system awk and sort.
run_agents() {
  HOME=/home/tester \
    CODEX_HOME=/home/tester/.codex \
    PATH="$FIXTURE_BIN:/usr/bin:/bin" \
    "$ROOT/scripts/agents.sh"
}

# Remove display-only ANSI codes and padding before comparing semantic fields.
normalize_rows() {
  awk -F'\t' '
    BEGIN { escape = sprintf("%c", 27) }
    {
      gsub(escape "\\[[0-9;]*m", "", $5)
      sub(/[[:space:]]+$/, "", $5)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $6)
      printf "%s|%s|%s|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5, $6, $7, $8
    }
  '
}

actual="$(run_agents | normalize_rows)"
expected=$'0|%1|101|dedicated|● waiting|1m|codex-alpha:0.0|~/project-a\n1|%3|303|loose|● idle|-|codex-user-project:2.0|~/project-c\n3|%2|202|loose|● working|0m|team:1.0|/srv/project-b'

if [ "$actual" != "$expected" ]; then
  printf 'agents.sh output mismatch\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

# Optional lsof enrichment must never be required for agents to remain listed.
without_rollouts="$(CODEX_TEST_DISABLE_LSOF=1 run_agents | normalize_rows)"
if [ "$(printf '%s\n' "$without_rollouts" | awk -F'|' '$6 == "-" { count++ } END { print count + 0 }')" -ne 3 ]; then
  printf 'agents disappeared or retained an age without rollout enrichment\n%s\n' "$without_rollouts" >&2
  exit 1
fi

printf 'agents_test: ok\n'
