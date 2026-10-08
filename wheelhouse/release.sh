#!/bin/sh
# Builds the Wheelhouse IDE that is handed to other people: a Release build that runs from any
# folder on any Mac, zipped with a checksum in wheelhouse/dist.
#   wheelhouse/release.sh 0.1.0
#
# It has its own bundle id, cmux's "staging" kind, so it keeps its own settings, runs next to an
# installed cmux and never updates itself from cmux's release feed. It is signed for local use
# only (no Developer ID), so a downloaded copy has to be approved once in
# System Settings > Privacy & Security.
#
# With an update key the build updates itself from this repository's releases: it gets the
# key's public half and the address of the latest release's appcast.xml, and its archive is
# signed with the key. Create the key once with
#   swift wheelhouse/update-key.swift new ~/.wheelhouse/update-key
# and keep a copy somewhere safe: installed copies accept only updates signed with it.
#   WHEELHOUSE_UPDATE_KEY    the key file (default: ~/.wheelhouse/update-key; empty: none)
#   WHEELHOUSE_UPDATE_FEED   the appcast address, when the releases are not on GitHub
set -eu
. "$(dirname "$0")/lib.sh"
version=${1:?usage: wheelhouse/release.sh <version>}
case "$version" in
  *[!0-9A-Za-z.-]*) echo "the version may hold letters, digits, dots and dashes" >&2; exit 2 ;;
esac
bundle_id="com.cmuxterm.app.staging.wheelhouse"
update_key="${WHEELHOUSE_UPDATE_KEY-$HOME/.wheelhouse/update-key}"
update_public_key="" update_feed="" slug=$(wheelhouse_repo_slug)
if [ -n "$update_key" ] && [ -f "$update_key" ]; then
  # The version becomes the build number, which is what one release is compared to the next by.
  case "$version" in
    *[!0-9.]*) echo "a build that updates itself needs a version of digits and dots; WHEELHOUSE_UPDATE_KEY= builds one that does not" >&2; exit 2 ;;
  esac
  update_feed="${WHEELHOUSE_UPDATE_FEED:-${slug:+https://github.com/$slug/releases/latest/download/appcast.xml}}"
  [ -n "$update_feed" ] || { echo "origin is not a GitHub repository; set WHEELHOUSE_UPDATE_FEED" >&2; exit 2; }
  update_public_key=$(swift "$WHEELHOUSE_ROOT/wheelhouse/update-key.swift" public "$update_key")
else
  echo "no update key at ${update_key:-(none)}: this build will not update itself" >&2
fi
# A folder outside the home directory keeps the builder's account name out of the binary.
derived="${WHEELHOUSE_RELEASE_DERIVED_DATA:-/tmp/wheelhouse-release}"
dist="$WHEELHOUSE_ROOT/wheelhouse/dist"
app="$dist/$WHEELHOUSE_APP_NAME.app"

cd "$WHEELHOUSE_ROOT"
# Recorded next to the archive: publish.sh only takes a build of a committed tree.
commit=$(git rev-parse HEAD)
[ -z "$(git status --porcelain)" ] || commit="$commit-dirty"
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
rm -rf "$app" "$archive" "$archive.sha256" "$archive.commit" "$archive.appcast.xml"
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
if [ -n "$update_public_key" ]; then
  set_plist CFBundleVersion "$version"
  set_plist SUFeedURL "$update_feed"
  set_plist SUPublicEDKey "$update_public_key"
  /usr/libexec/PlistBuddy -c "Delete :WheelhouseUpdates" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :WheelhouseUpdates bool true" "$plist"
fi
# The app and the bundled `cmux` command find each other through these.
/usr/libexec/PlistBuddy -c "Delete :LSEnvironment" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$plist"
set_plist LSEnvironment:CMUX_BUNDLE_ID "$bundle_id"
set_plist LSEnvironment:CMUX_SOCKET_PATH /tmp/cmux-staging-wheelhouse.sock

python3 "$WHEELHOUSE_ROOT/wheelhouse/brand/apply.py" "$app"
wheelhouse_bundle_board "$app" "$arch"

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
printf '%s\n' "$commit" > "$archive.commit"

if [ -n "$update_public_key" ]; then
  signature=$(swift "$WHEELHOUSE_ROOT/wheelhouse/update-key.swift" sign "$update_key" "$archive")
  downloads="${WHEELHOUSE_UPDATE_DOWNLOADS:-https://github.com/$slug/releases/download/v$version}"
  notes="${slug:+https://github.com/$slug/releases/tag/v$version}"
  cat > "$archive.appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$WHEELHOUSE_APP_NAME</title>
    <item>
      <title>$version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist")</sparkle:minimumSystemVersion>${notes:+
      <sparkle:releaseNotesLink>$notes</sparkle:releaseNotesLink>}
      <enclosure url="$downloads/$(basename "$archive")" length="$(stat -f %z "$archive")" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
XML
  echo "updates itself from $update_feed"
fi
echo "Wheelhouse IDE $version: $archive ($(du -h "$archive" | cut -f1))"
cat "$archive.sha256"
