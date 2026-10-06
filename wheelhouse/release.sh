#!/bin/sh
# Builds the Wheelhouse IDE that is handed to other people: a Release build that runs from any
# folder on any Mac, zipped with a checksum in wheelhouse/dist.
#   wheelhouse/release.sh 0.1.0
#
# It has its own bundle id, cmux's "staging" kind, so it keeps its own settings, runs next to an
# installed cmux and never updates itself from cmux's release feed. It is signed for local use
# only (no Developer ID), so a downloaded copy has to be approved once in
# System Settings > Privacy & Security.
set -eu
. "$(dirname "$0")/lib.sh"
version=${1:?usage: wheelhouse/release.sh <version>}
case "$version" in
  *[!0-9A-Za-z.-]*) echo "the version may hold letters, digits, dots and dashes" >&2; exit 2 ;;
esac
bundle_id="com.cmuxterm.app.staging.wheelhouse"
# A folder outside the home directory keeps the builder's account name out of the binary.
derived="${WHEELHOUSE_RELEASE_DERIVED_DATA:-/tmp/wheelhouse-release}"
dist="$WHEELHOUSE_ROOT/wheelhouse/dist"
app="$dist/$WHEELHOUSE_APP_NAME.app"

cd "$WHEELHOUSE_ROOT"
# The Release configuration asks for cmux's developer certificate; build unsigned, sign below.
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build
built="$derived/Build/Products/Release/cmux.app"
[ -d "$built" ] || { echo "the build did not produce $built" >&2; exit 1; }

case "$(lipo -archs "$built/Contents/MacOS/cmux")" in
  *arm64*x86_64* | *x86_64*arm64*) arch=universal ;;
  *) arch=$(lipo -archs "$built/Contents/MacOS/cmux" | tr -d ' ') ;;
esac
archive="$dist/Wheelhouse-IDE-$version-macos-$arch.zip"
rm -rf "$app" "$archive" "$archive.sha256"
mkdir -p "$dist"
cp -R "$built" "$app"

plist="$app/Contents/Info.plist"
set_plist() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"
}
set_plist CFBundleName "$WHEELHOUSE_APP_NAME"
set_plist CFBundleDisplayName "$WHEELHOUSE_APP_NAME"
set_plist CFBundleIdentifier "$bundle_id"
set_plist WheelhouseVersion "$version"
# The app and the bundled `cmux` command find each other through these.
/usr/libexec/PlistBuddy -c "Delete :LSEnvironment" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$plist"
set_plist LSEnvironment:CMUX_BUNDLE_ID "$bundle_id"
set_plist LSEnvironment:CMUX_SOCKET_PATH /tmp/cmux-staging-wheelhouse.sock

python3 "$WHEELHOUSE_ROOT/wheelhouse/brand/apply.py" "$app"
wheelhouse_bundle_board "$app"

# Source paths compiled into the binaries name the builder's home folder. They mean nothing
# on another Mac, so the folder's name is overwritten with one of the same length.
python3 - "$app" "$HOME" <<'PY' | while IFS= read -r changed; do
import os, sys
root, home = sys.argv[1], sys.argv[2].encode()
lead = b"/Users/" if home.startswith(b"/Users/") else b"/"
neutral = (lead + b"builder" + b"_" * len(home))[:len(home)]
for folder, _, names in os.walk(root):
    for name in names:
        path = os.path.join(folder, name)
        if os.path.islink(path):
            continue
        with open(path, "rb") as f:
            data = f.read()
        if home in data:
            with open(path, "wb") as f:
                f.write(data.replace(home, neutral))
            print(path)
PY
  # A changed program needs a fresh signature to be allowed to run. The ones among the
  # resources are signed here; the app's own program and its bundles by the pass below.
  case "$changed" in
    "$app/Contents/Resources/"*)
      if file -b "$changed" | grep -q "Mach-O"; then
        /usr/bin/codesign --force --sign - --timestamp=none "$changed"
      fi ;;
  esac
done

# Signed for local use, like a developer build: no certificate, no entitlements.
/usr/bin/codesign --force --deep --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --deep --strict "$app"

# Nothing in the bundle may point back at the machine that built it.
if grep -rqF "$HOME" "$app"; then
  echo "the app still names $HOME:" >&2
  grep -rlF "$HOME" "$app" >&2
  exit 1
fi

/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$app" "$archive"
(cd "$dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Wheelhouse IDE $version: $archive ($(du -h "$archive" | cut -f1))"
cat "$archive.sha256"
