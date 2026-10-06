#!/bin/sh
# Clears what earlier launches of a Wheelhouse IDE dev build left behind. The preferences
# themselves (no telemetry, no cmux account or Pro controls) are built into the app:
# Sources/WheelhouseDefaults.swift. build.sh runs this; safe to run again.
set -eu
. "$(dirname "$0")/lib.sh"
domain="com.cmuxterm.app.debug.$WHEELHOUSE_TAG"

# Left over from launches that did ask cmux's feature-flag service.
defaults delete "$domain" cmux.flags.releaseControlDistinctID 2>/dev/null || true
defaults read "$domain" 2>/dev/null | sed -n 's/^ *"\{0,1\}\(cmux\.flags\.remote\.[^" ]*\)"\{0,1\} = .*/\1/p' |
  while read -r key; do defaults delete "$domain" "$key"; done
