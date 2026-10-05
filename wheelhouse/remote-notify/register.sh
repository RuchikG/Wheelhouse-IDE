#!/bin/sh
# Runs on the SSH host: registers ~/.claude/cmux-notify-hook.sh for the Notification and Stop
# events in ~/.claude/settings.json. Safe to run again.
set -eu
command -v jq >/dev/null 2>&1 || { echo "jq is required on this host" >&2; exit 1; }
hook="$HOME/.claude/cmux-notify-hook.sh"
settings="$HOME/.claude/settings.json"
chmod +x "$hook"
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak-cmux-notify"
jq --arg h "$hook" '
  def entry: [{hooks: [{type: "command", command: $h, timeout: 10}]}];
  def add(ev): .hooks[ev] = ((.hooks[ev] // []) | map(select(any(.hooks[]?; .command == $h) | not)) + entry);
  add("Notification") | add("Stop")
' "$settings.bak-cmux-notify" > "$settings.tmp"
mv "$settings.tmp" "$settings"
echo "registered $hook in $settings (previous version: $settings.bak-cmux-notify)"
