#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - script/Info.plist)"
dmg="$PWD/outputs/LidPulse-$version.dmg"
mkdir -p outputs
stage="$(mktemp -d "${TMPDIR:-/tmp}/lidpulse-release.XXXXXX")"
trap 'rm -R -- "$stage"' EXIT
mkdir "$stage/volume"

LIDPULSE_APP_BUNDLE="$stage/volume/LidPulse.app" LIDPULSE_STRIP_DEBUG=1 ./script/build_and_run.sh --build
ln -s /Applications "$stage/volume/Applications"
/usr/bin/hdiutil create -volname "LidPulse" -srcfolder "$stage/volume" -fs HFS+ -format UDZO "$stage/LidPulse.dmg"
/usr/bin/hdiutil verify "$stage/LidPulse.dmg"
/bin/mv "$stage/LidPulse.dmg" "$dmg"
echo "$dmg"
