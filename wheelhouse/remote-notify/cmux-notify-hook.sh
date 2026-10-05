#!/bin/sh
# Claude Code hook (Notification, Stop) for an SSH host: forwards to the cmux app through the
# `cmux ssh` relay, so the workspace shows a notification when the agent needs input or finishes.
# Does nothing outside a `cmux ssh` terminal, or when the relay has its own Claude hooks.
case "${CMUX_SOCKET_PATH:-}" in
  "" | /*) exit 0 ;;
esac
[ -n "${CMUX_WORKSPACE_ID:-}" ] || exit 0
cmux="$HOME/.cmux/bin/cmux"
[ -x "$cmux" ] || exit 0
"$cmux" claude-wrapper --cmux-probe >/dev/null 2>&1 && exit 0

payload=$(cat)
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)
case "$event" in
  Notification) body=$(printf '%s' "$payload" | jq -r '.message // "Needs your input"' 2>/dev/null) ;;
  Stop) body="Finished" ;;
  *) exit 0 ;;
esac
dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

timeout 5 "$cmux" notify --title "Claude Code" --subtitle "$(hostname -s): ${dir##*/}" --body "$body" >/dev/null 2>&1 &
exit 0
