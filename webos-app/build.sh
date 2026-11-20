#!/bin/sh
# Build the FW Block TV app (IPK) and its Homebrew Channel manifest.
#
# Usage: webos-app/build.sh [--no-package]
#   --no-package  only assemble webos-app/dist (for tests, no ares-package)
# Needs: node, npm; ares-package (npm install -g @webos-tools/cli) to package.
# Output: webos-app/dist, webos-app/out/<id>_<version>_all.ipk and its manifest
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/fw-block.sh")

DIST="$HERE/dist"
OUT="$HERE/out"
rm -rf "$DIST" "$OUT"
mkdir -p "$DIST/assets" "$OUT" "$ROOT/.cache"
cp -R "$HERE/src/." "$DIST/"
cp "$ROOT/fw-block.sh" "$ROOT/update.js" "$ROOT/CHANGELOG.md" "$DIST/assets/"
chmod 755 "$DIST/assets/fw-block.sh"
cp "$ROOT/LICENSE" "$DIST/LICENSE"

# fetch NAME VERSION FILE-IN-PACKAGE SHA256 CACHE-NAME: one file from npm,
# kept only if its checksum matches
fetch() {
    _c="$ROOT/.cache/$5"
    if [ ! -f "$_c" ]; then
        _t=$(mktemp -d)
        (cd "$_t" && npm pack --silent "$1@$2" >/dev/null && tar xzf ./*.tgz)
        cp "$_t/package/$3" "$_c"
        rm -rf "$_t"
    fi
    echo "$4  $_c" | sha256sum -c - >/dev/null || { echo "$5: checksum mismatch" >&2; rm -f "$_c"; exit 1; }
}
# Ed25519 for checking an update's signature on any webOS's Node.js
# (public domain, TweetNaCl-js)
fetch tweetnacl 1.0.3 nacl-fast.min.js 3ec535c004aeeb225785d8e93fb33bf99f52e399bd7dfc01969b5629baea5131 tweetnacl-1.0.3-nacl-fast.min.js
cp "$ROOT/.cache/tweetnacl-1.0.3-nacl-fast.min.js" "$DIST/assets/nacl-fast.min.js"

node -e '
const fs = require("fs");
const f = process.argv[1];
const a = JSON.parse(fs.readFileSync(f, "utf8"));
a.version = process.argv[2];
fs.writeFileSync(f, JSON.stringify(a, null, 4) + "\n");
' "$DIST/appinfo.json" "$VERSION"

if [ "${1:-}" = --no-package ]; then echo "Assembled $DIST (v$VERSION)"; exit 0; fi

ares-package --no-minify "$DIST" -o "$OUT" >/dev/null
IPK=$(ls "$OUT"/*.ipk)
echo "Built $IPK"
node "$HERE/gen-manifest.js" "$DIST/appinfo.json" "$IPK" "$OUT"
