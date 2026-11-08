#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-run}"
case "$mode" in run|--build|--verify|--logs|--telemetry|--debug) ;; *) exit 2 ;; esac
app="${LIDPULSE_APP_BUNDLE:-$PWD/outputs/LidPulse.app}"

if [[ "$mode" != --build ]] && /usr/bin/pgrep -xq LidPulse; then
    /usr/bin/pkill -TERM -x LidPulse
    for _ in {1..30}; do
        /usr/bin/pgrep -xq LidPulse || break
        sleep 0.2
    done
    if /usr/bin/pgrep -xq LidPulse; then
        echo 'LidPulse is still running; quit it from the menu bar first.' >&2
        exit 1
    fi
fi
swift build -c release -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
binary="$(swift build -c release --show-bin-path)/LidPulse"
mkdir -p "$app/Contents/MacOS"
install -m 755 "$binary" "$app/Contents/MacOS/LidPulse"
install -m 644 script/Info.plist "$app/Contents/Info.plist"
if [[ "${LIDPULSE_STRIP_DEBUG:-0}" == 1 ]]; then
    /usr/bin/strip -S "$app/Contents/MacOS/LidPulse"
fi
codesign --force --sign "${LIDPULSE_SIGN_IDENTITY:--}" --options runtime --entitlements script/entitlements.plist "$app"
codesign --verify --strict "$app"

case "$mode" in
    --build) ;;
    --debug) /usr/bin/open -n "$app"; lldb -n LidPulse -w ;;
    --logs|--telemetry) /usr/bin/open -n "$app"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.lidpulse"' ;;
    --verify)
        /usr/bin/open -n "$app"
        sleep 1
        /usr/bin/pgrep -x LidPulse
        ;;
    *) /usr/bin/open -n "$app" ;;
esac
