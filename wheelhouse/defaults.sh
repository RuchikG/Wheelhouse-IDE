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
