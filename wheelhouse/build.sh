#!/bin/sh
# Builds Wheelhouse IDE: a tagged dev build of this repository, named and worded as Wheelhouse IDE.
# Extra arguments go to scripts/reload.sh.
#   wheelhouse/build.sh
#   WHEELHOUSE_TAG=mine wheelhouse/build.sh
set -eu
. "$(dirname "$0")/lib.sh"
case "$WHEELHOUSE_TAG" in
  *[!a-z0-9-]*) echo "WHEELHOUSE_TAG must be lowercase letters, digits and dashes" >&2; exit 2 ;;
esac
export CMUX_DEV_BACKEND_MODE="${CMUX_DEV_BACKEND_MODE:-local}"
"$WHEELHOUSE_ROOT/scripts/reload.sh" --tag "$WHEELHOUSE_TAG" --name "$WHEELHOUSE_APP_NAME" "$@"

[ -d "$WHEELHOUSE_APP_PATH" ] || { echo "build did not produce $WHEELHOUSE_APP_PATH" >&2; exit 1; }
python3 "$WHEELHOUSE_ROOT/wheelhouse/brand/apply.py" "$WHEELHOUSE_APP_PATH"
# The string tables are sealed resources; sign again the way reload.sh does.
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der "$WHEELHOUSE_APP_PATH"
"$WHEELHOUSE_ROOT/wheelhouse/defaults.sh"
echo "Wheelhouse IDE: $WHEELHOUSE_APP_PATH (open it with wheelhouse/open.sh)"
