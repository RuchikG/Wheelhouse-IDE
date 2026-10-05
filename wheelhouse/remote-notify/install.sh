#!/bin/sh
# Installs the notify hook for Claude Code on an SSH host.
#   ./install.sh <ssh-destination>
set -eu
[ $# -eq 1 ] || { echo "usage: install.sh <ssh-destination>" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
ssh "$1" 'mkdir -p ~/.claude'
scp -q "$here/cmux-notify-hook.sh" "$1:.claude/cmux-notify-hook.sh"
ssh "$1" 'sh -s' < "$here/register.sh"
