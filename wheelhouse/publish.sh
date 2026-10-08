#!/bin/sh
# Publishes a build made by wheelhouse/release.sh as a GitHub release of this repository.
#   wheelhouse/publish.sh 0.1.1
#   wheelhouse/publish.sh 0.1.1 --notes notes.md   release text from a file
#   wheelhouse/publish.sh 0.1.1 --draft            upload everything, leave it unpublished
#   wheelhouse/publish.sh 0.1.1 --check            run the checks, change nothing
#
# It refuses unless the archive was built from the commit that is checked out, that commit is
# on origin/main, and the version has no release yet. The release is created as a draft, gets
# its files, and only then becomes public; afterwards the archive is downloaded back and its
# checksum compared. The GitHub token comes from git's credential helper and is never printed.
set -eu
. "$(dirname "$0")/lib.sh"
version=${1:?usage: wheelhouse/publish.sh <version> [--notes <file>] [--draft] [--check]}
shift
case "$version" in
  *[!0-9A-Za-z.-]*) echo "the version may hold letters, digits, dots and dashes" >&2; exit 2 ;;
esac
notes="" draft=0 check=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) notes=${2:?--notes needs a file}; shift 2 ;;
    --draft) draft=1; shift ;;
    --check) check=1; shift ;;
    *) echo "unexpected argument: $1" >&2; exit 2 ;;
  esac
done
[ -z "$notes" ] || [ -f "$notes" ] || { echo "no such file: $notes" >&2; exit 2; }

fail() { echo "not published: $*" >&2; exit 1; }

cd "$WHEELHOUSE_ROOT"
dist="$WHEELHOUSE_ROOT/wheelhouse/dist"
tag="v$version"
archive=$(ls "$dist"/Wheelhouse-IDE-"$version"-macos-*.zip 2>/dev/null | head -1)
[ -n "$archive" ] || fail "no archive for $version in wheelhouse/dist; run wheelhouse/release.sh $version"
name=$(basename "$archive")
[ -f "$archive.sha256" ] || fail "$name has no checksum file next to it"
(cd "$dist" && shasum -a 256 -c "$name.sha256" >/dev/null) || fail "$name does not match its checksum file"
[ -f "$archive.commit" ] || fail "$name does not say which commit it was built from; build it again"

head=$(git rev-parse HEAD)
built=$(cat "$archive.commit")
[ -z "$(git status --porcelain)" ] || fail "the working tree has uncommitted changes"
[ "$built" = "$head" ] || fail "$name was built from $built, and $head is checked out"
git fetch --quiet origin main
git merge-base --is-ancestor "$head" origin/main || fail "$head is not on origin/main; push first"

slug=$(wheelhouse_repo_slug)
[ -n "$slug" ] || fail "origin is not a GitHub repository"
api="https://api.github.com/repos/$slug"

token=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')
[ -n "$token" ] || fail "git has no GitHub credential for this account"
# The token goes to curl on standard input so that it is in no command line.
github() {
  printf 'header = "Authorization: Bearer %s"\n' "$token" |
    curl -K - -sS -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1"; }

status=$(github -o /dev/null -w '%{http_code}' "$api/releases/tags/$tag")
case "$status" in
  404) ;;
  200) fail "$tag already has a release" ;;
  *) fail "GitHub answered $status when asked about $tag" ;;
esac
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  fail "the tag $tag already exists on origin"
fi

echo "$name ($(du -h "$archive" | cut -f1 | tr -d ' ')), built from $(git rev-parse --short "$head"), to $slug as $tag"
[ -f "$archive.appcast.xml" ] || echo "note: this build does not update itself (it was built without an update key)"
if [ "$check" = 1 ]; then
  echo "checks passed; nothing was published"
  exit 0
fi

body=$(python3 - "$version" "$tag" "$head" "$notes" <<'PY'
import json, sys
version, tag, commit, notes = sys.argv[1:5]
text = open(notes).read() if notes else (
    "Download the zip, unzip it and move Wheelhouse IDE to Applications. The build is not signed "
    "with an Apple Developer ID, so the first time macOS asks you to allow it under "
    "System Settings > Privacy & Security.")
print(json.dumps({"tag_name": tag, "target_commitish": commit, "name": "Wheelhouse IDE " + version,
                  "body": text, "draft": True}))
PY
)
created=$(github -X POST "$api/releases" -d "$body")
id=$(printf '%s' "$created" | field id)
[ -n "$id" ] || fail "GitHub did not create the release: $(printf '%s' "$created" | field message)"
page=$(printf '%s' "$created" | field html_url)
echo "draft created: $page"

# upload <file> <content type> [<name on the release>]
upload() {
  as=${3:-$(basename "$1")}
  uploaded=$(github -X POST -H "Content-Type: $2" --data-binary @"$1" \
    "https://uploads.github.com/repos/$slug/releases/$id/assets?name=$as")
  size=$(printf '%s' "$uploaded" | field size)
  [ "$size" = "$(stat -f %z "$1")" ] ||
    fail "$as did not upload whole; the draft is still at $page"
  echo "uploaded $as"
}
upload "$archive" application/zip
upload "$archive.sha256" text/plain
# Installed copies look for this file on the latest release to learn about a newer version.
[ ! -f "$archive.appcast.xml" ] || upload "$archive.appcast.xml" application/xml appcast.xml

if [ "$draft" = 1 ]; then
  echo "left as a draft: $page"
  exit 0
fi
published=$(github -X PATCH "$api/releases/$id" -d '{"draft": false}')
page=$(printf '%s' "$published" | field html_url)
[ -n "$page" ] || fail "the release stayed a draft: $(printf '%s' "$published" | field message)"

# What people will download has to be what was built.
want=$(cut -d' ' -f1 "$archive.sha256")
got=$(curl -sSL "https://github.com/$slug/releases/download/$tag/$name" | shasum -a 256 | cut -d' ' -f1)
[ "$got" = "$want" ] || fail "the published $name has checksum $got, expected $want; see $page"
if [ -f "$archive.appcast.xml" ]; then
  curl -sSL "https://github.com/$slug/releases/latest/download/appcast.xml" | cmp -s - "$archive.appcast.xml" ||
    fail "the latest release does not serve this version's appcast.xml, so installed copies will not see it; see $page"
fi
echo "published and verified: $page"
