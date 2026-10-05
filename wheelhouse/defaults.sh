#!/bin/sh
# Wheelhouse IDE's preferences on top of cmux's defaults. build.sh runs this; safe to run again.
# They take effect the next time the app starts.
set -eu
. "$(dirname "$0")/lib.sh"
domain="com.cmuxterm.app.debug.$WHEELHOUSE_TAG"

# cmux Pro upgrade prompts (sidebar, Settings, command palette, Help menu), the cmux account
# control and the phone pairing button in the sidebar footer.
defaults write "$domain" cmux.flags.override.pro-upgrade-ui-enabled-release -bool false
defaults write "$domain" cmux.flags.override.sidebar-account-button-enabled-release -bool false
defaults write "$domain" cmux.flags.override.mobile-connect-button-enabled-release -bool false
# The red "dev build" label under the sidebar.
defaults write "$domain" showSidebarDevBuildBanner -bool false
# No analytics, crash reports or feature-flag requests go to cmux's services (flags then use
# their built-in defaults and the overrides above). This is the "Send anonymous telemetry"
# setting; the app reads it at launch.
defaults write "$domain" sendAnonymousTelemetry -bool false
# Left over from launches that did ask the flag service.
defaults delete "$domain" cmux.flags.releaseControlDistinctID 2>/dev/null || true
defaults read "$domain" 2>/dev/null | sed -n 's/^ *"\{0,1\}\(cmux\.flags\.remote\.[^" ]*\)"\{0,1\} = .*/\1/p' |
  while read -r key; do defaults delete "$domain" "$key"; done
