# Shared by the wheelhouse/ scripts: where the tagged dev build of Wheelhouse IDE lives.
# WHEELHOUSE_TAG picks the build (default: wheelhouse); each tag is its own app with its own
# settings, socket and build directory.
WHEELHOUSE_APP_NAME="Wheelhouse IDE"
WHEELHOUSE_TAG="${WHEELHOUSE_TAG:-wheelhouse}"
WHEELHOUSE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHEELHOUSE_DERIVED_DATA="${CMUX_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/cmux-$WHEELHOUSE_TAG}"
WHEELHOUSE_APP_PATH="$WHEELHOUSE_DERIVED_DATA/Build/Products/Debug/$WHEELHOUSE_APP_NAME.app"
WHEELHOUSE_SOCKET_PATH="/tmp/cmux-debug-$WHEELHOUSE_TAG.sock"
