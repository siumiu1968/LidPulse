#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./script/package_dmg.sh
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - script/Info.plist)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/lidpulse-update.XXXXXX")"
trap 'rm -R -- "$stage"' EXIT
cp "outputs/LidPulse-$version.dmg" "$stage/"
cp "docs/release-notes/$version.md" "$stage/LidPulse-$version.md"
if [[ -f docs/appcast.xml ]]; then cp docs/appcast.xml "$stage/"; fi
tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
"$tools/generate_appcast" --account local.lidpulse --embed-release-notes \
    --download-url-prefix "https://github.com/siumiu1968/LidPulse/releases/download/v$version/" \
    --maximum-deltas 0 -o "$stage/appcast.xml" "$stage"
"$tools/sign_update" --account local.lidpulse --verify "$stage/appcast.xml"
cp "$stage/appcast.xml" docs/appcast.xml
echo "Prepared signed update feed: docs/appcast.xml"
