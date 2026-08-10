#!/usr/bin/env bash
# One-time, idempotent installer: registers this plugin's Notification and
# Stop hooks in Claude Code's global settings.json, so hook-notify.sh fires
# on real state transitions instead of notify.sh polling for them.
#
# Rewrites the whole settings.json through jq, which reformats it (spacing
# and key order for untouched keys are preserved, but overall indentation
# style may change). Defaults to a dry run that prints the diff; pass
# --apply to actually write.
set -uo pipefail
# -P: canonicalize through symlinks (e.g. a symlinked ~/.config/tmux), so the
# path baked into settings.json is stable no matter which literal route the
# plugin was loaded through — otherwise re-running from a different route
# looks like a different command and adds a duplicate hook entry.
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

apply=0
[ "${1:-}" = "--apply" ] && apply=1

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

hook_script="$DIR/hook-notify.sh"
[ -x "$hook_script" ] || echo "warning: $hook_script is not executable (run: chmod +x '$hook_script')" >&2

notification_cmd="\"$hook_script\" waiting"
stop_cmd="\"$hook_script\" done"

if [ -f "$settings_file" ]; then
  current="$(cat "$settings_file")"
else
  current='{}'
fi

printf '%s' "$current" | jq empty >/dev/null 2>&1 || {
  echo "$settings_file is not valid JSON, aborting" >&2
  exit 1
}

updated="$(printf '%s' "$current" | jq \
  --arg ncmd "$notification_cmd" \
  --arg scmd "$stop_cmd" '
  def has_cmd(event; cmd): ((.hooks[event] // []) | any(.[]?.hooks[]?.command == cmd; .));

  (if has_cmd("Notification"; $ncmd) then .
   else .hooks.Notification = ((.hooks.Notification // []) + [{matcher: "", hooks: [{type: "command", command: $ncmd}]}])
   end)
  | (if has_cmd("Stop"; $scmd) then .
     else .hooks.Stop = ((.hooks.Stop // []) + [{hooks: [{type: "command", command: $scmd}]}])
     end)
')"

if [ "$(printf '%s' "$updated" | jq -S .)" = "$(printf '%s' "$current" | jq -S .)" ]; then
  echo "Notify hooks already installed in $settings_file, nothing to do."
  exit 0
fi

if [ "$apply" -eq 1 ]; then
  # mktemp, not a fixed "$settings_file.tmp": two overlapping runs (e.g. a
  # doubled config reload) would otherwise share that name and could race
  # each other's write before either side's mv lands.
  tmp="$(mktemp "$settings_file.XXXXXX")"
  printf '%s\n' "$updated" >"$tmp"
  mv "$tmp" "$settings_file"
  echo "Installed notify hooks into $settings_file"
else
  echo "Dry run — would write $settings_file:"
  diff <(printf '%s\n' "$current" | jq .) <(printf '%s\n' "$updated" | jq .)
  echo
  echo "Re-run with --apply to write."
fi
