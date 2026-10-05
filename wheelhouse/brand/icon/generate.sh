#!/bin/sh
# Renders wheelhouse-ide.svg into the app's icon assets. Run after editing the SVG, then rebuild.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
assets="$here/../../../Assets.xcassets"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc -O -parse-as-library "$here/render.swift" -o "$tmp/render"

render() { "$tmp/render" "$here/wheelhouse-ide.svg" "$1" "$2"; }

# Dock and Finder icon of the dev build.
set_dir="$assets/AppIcon-Debug.appiconset"
for points in 16 32 128 256 512; do
  render "$points" "$set_dir/$points.png"
  render "$((points * 2))" "$set_dir/$points@2x.png"
done
# The app swaps these in at runtime to follow the light or dark appearance.
render 1024 "$assets/AppIconLight.imageset/AppIconLight.png"
render 1024 "$assets/AppIconDark.imageset/AppIconDark.png"
echo "icon assets written under $assets"
