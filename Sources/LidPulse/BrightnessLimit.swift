import Foundation

enum BrightnessLimit {
    private static let state = "/var/db/local.lidpulse.brightness"
    static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: state + "/original.plist")
    }

    enum Result { case changed, cancelled, failed }

    @MainActor static func setUnlocked(_ unlock: Bool, language: Language) -> Result {
        let prompt = unlock
            ? language.text("LidPulse 想解除機蓋 Logo 嘅環境光亮度限制。", "LidPulse wants to remove the lid logo’s ambient-light brightness limit.")
            : language.text("LidPulse 想還原原本嘅機蓋 Logo 亮度限制。", "LidPulse wants to restore the previous lid logo brightness limits.")
        func literal(_ string: String) -> String {
            "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let command = "action=" + (unlock ? "unlock\n" : "restore\n") + script
        let source = "do shell script " + literal(command) + " with prompt " + literal(prompt) + " with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return .failed }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error {
            return (error[NSAppleScript.errorNumber] as? Int) == -128 ? .cancelled : .failed
        }
        return .changed
    }

    // This script is bundled as code, not read from a user-writable file at authorization time.
    // The two preference values match the hardware’s normal lower and upper operating levels.
    static let script = #"""
    set -eu
    umask 077
    domain=com.apple.CoreBrightness
    state=/var/db/local.lidpulse.brightness
    min=LEPWMLuxToMinNitsRestrictionMapping
    max=LEPWMLuxToMaxNitsRestrictionMapping
    backup="$state/original.plist"
    [ ! -L "$state" ] || exit 20
    if [ ! -d "$state" ]; then /bin/mkdir -m 755 "$state"; fi
    /bin/mkdir "$state/lock" || exit 21
    trap '/bin/unlink "$state/lock/export.plist" 2>/dev/null || :; /bin/rmdir "$state/lock"' EXIT
    [ ! -L "$backup" ] || exit 22

    get_xml() {
        /usr/bin/plutil -extract "$1" xml1 -o - "$backup" 2>/dev/null |
            /usr/bin/sed -e '1,/<plist[^>]*>/d' -e '/<\/plist>/,$d'
    }

    restore_key() {
        key="$1"
        old="$(get_xml "$key")"
        if [ -n "$old" ]; then
            /usr/bin/defaults write "$domain" "$key" "$old"
        elif /usr/bin/defaults read "$domain" "$key" >/dev/null 2>&1; then
            /usr/bin/defaults delete "$domain" "$key"
        fi
    }

    restart_brightness() {
        /usr/bin/killall -TERM corebrightnessd
    }

    if [ "$action" = unlock ]; then
        if [ ! -f "$backup" ]; then
            tmp="$state/lock/export.plist"
            if ! /usr/bin/defaults export "$domain" - > "$tmp" 2>/dev/null; then
                /usr/bin/printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict/></plist>' > "$tmp"
            fi
            /usr/bin/plutil -lint "$tmp" >/dev/null
            /bin/mv "$tmp" "$backup"
        fi
        /usr/bin/plutil -lint "$backup" >/dev/null
        minimum='<array><array><real>0</real><real>12.5</real></array><array><real>3.4e38</real><real>12.5</real></array></array>'
        maximum='<array><array><real>0</real><real>1000</real></array><array><real>3.4e38</real><real>1000</real></array></array>'
        if /usr/bin/defaults write "$domain" "$min" "$minimum" &&
           /usr/bin/defaults write "$domain" "$max" "$maximum" &&
           restart_brightness; then
            exit 0
        fi
        if restore_key "$min" && restore_key "$max"; then
            restart_brightness && /bin/unlink "$backup"
        fi
        exit 23
    fi

    [ "$action" = restore ] && [ -f "$backup" ] || exit 24
    /usr/bin/plutil -lint "$backup" >/dev/null
    restore_key "$min"
    restore_key "$max"
    restart_brightness
    /bin/unlink "$backup"
    """#
}
