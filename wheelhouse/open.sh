#!/bin/sh
# Opens the built Wheelhouse IDE. Arguments go to open(1), e.g. -g to stay in the background.
set -eu
. "$(dirname "$0")/lib.sh"
[ -d "$WHEELHOUSE_APP_PATH" ] || { echo "not built yet: run wheelhouse/build.sh" >&2; exit 1; }
exec open "$@" "$WHEELHOUSE_APP_PATH"
