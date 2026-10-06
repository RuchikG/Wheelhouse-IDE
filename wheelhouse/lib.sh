# Shared by the wheelhouse/ scripts: where the tagged dev build of Wheelhouse IDE lives.
# WHEELHOUSE_TAG picks the build (default: wheelhouse); each tag is its own app with its own
# settings, socket and build directory.
WHEELHOUSE_APP_NAME="Wheelhouse IDE"
WHEELHOUSE_TAG="${WHEELHOUSE_TAG:-wheelhouse}"
WHEELHOUSE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHEELHOUSE_DERIVED_DATA="${CMUX_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/cmux-$WHEELHOUSE_TAG}"
WHEELHOUSE_APP_PATH="$WHEELHOUSE_DERIVED_DATA/Build/Products/Debug/$WHEELHOUSE_APP_NAME.app"
WHEELHOUSE_SOCKET_PATH="/tmp/cmux-debug-$WHEELHOUSE_TAG.sock"

# Puts the board command and its sidebar script inside an app bundle, where the app's own
# terminals find `proj` on their PATH. Without Go the app is built without them.
wheelhouse_bundle_board() {
  if ! command -v go >/dev/null 2>&1; then
    echo "go not found: $1 is built without the board command (proj)" >&2
    return 0
  fi
  (cd "$WHEELHOUSE_ROOT/wheelhouse/board" &&
    go build -trimpath -ldflags "-s -w" -o "$1/Contents/Resources/bin/proj" ./cmd/proj)
  mkdir -p "$1/Contents/Resources/sidebars"
  cp "$WHEELHOUSE_ROOT/wheelhouse/board/sidebars/projects-board.js" "$1/Contents/Resources/sidebars/"
}
