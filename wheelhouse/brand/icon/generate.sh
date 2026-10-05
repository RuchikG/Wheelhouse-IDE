#!/bin/sh
# Renders the light and dark icon SVGs into the app's icon assets. Run after editing an SVG, then rebuild.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
assets="$here/../../../Assets.xcassets"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc -O -parse-as-library "$here/render.swift" -o "$tmp/render"

render() { "$tmp/render" "$here/wheelhouse-ide-$1.svg" "$2" "$3"; }

# Finder icon of the dev build, and its Dock icon until the app has started.
set_dir="$assets/AppIcon-Debug.appiconset"
for points in 16 32 128 256 512; do
  render dark "$points" "$set_dir/$points.png"
  render dark "$((points * 2))" "$set_dir/$points@2x.png"
done
# The running app shows the one that matches its light or dark theme.
render light 1024 "$assets/AppIconLight.imageset/AppIconLight.png"
render dark 1024 "$assets/AppIconDark.imageset/AppIconDark.png"
echo "icon assets written under $assets"
