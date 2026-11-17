import Foundation
import ObjectiveC
import Darwin

/// Keeps the native logo driver active without changing the physical lid state.
final class ClosedLidLogo {
    private typealias Setter = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Bool
    private typealias KeyboardSetter = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool
    private let client: NSObject
    private(set) var active = false
    private static var marker: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LidPulse/native-lid-override")
    }

    init(client: NSObject) { self.client = client }
    var isClosed: Bool { LidGuard.isClosed }

    func begin() -> Bool {
        guard !active else { return true }
        guard isClosed else { return false }
        do {
            try FileManager.default.createDirectory(at: Self.marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: Self.marker, options: .atomic)
        } catch { return false }
        guard Self.setClamshell(false, client: client) else {
            try? FileManager.default.removeItem(at: Self.marker)
            return false
        }
        // Keep the keyboard dark while overriding only the logo.
        if let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
            let keyboard = type.init()
            let ids = NSSelectorFromString("copyKeyboardBacklightIDs")
            let set = NSSelectorFromString("setProperty:withKey:keyboardID:")
            if keyboard.responds(to: ids), keyboard.responds(to: set),
               let keyboards = keyboard.perform(ids)?.takeRetainedValue() as? [NSNumber],
               let method = keyboard.method(for: set) {
                let setter = unsafeBitCast(method, to: KeyboardSetter.self)
                for id in keyboards { _ = setter(keyboard, set, true as NSNumber, "CBClamshellState", id.uint64Value) }
            }
        }
        active = true
        return true
    }

    @discardableResult func release() -> Bool {
        guard active else { return false }
        guard Self.setClamshell(isClosed, client: client) else { return false }
        active = false
        try? FileManager.default.removeItem(at: Self.marker)
        return true
    }

    private static func setClamshell(_ closed: Bool, client: NSObject) -> Bool {
        let selector = NSSelectorFromString("setProperty:forKey:")
        guard client.responds(to: selector), let method = client.method(for: selector) else { return false }
        return unsafeBitCast(method, to: Setter.self)(client, selector, closed as NSNumber, "ClamshellUpdate")
    }

    static func recoverAfterExit() {
        guard FileManager.default.fileExists(atPath: marker.path),
              dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL) != nil,
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              setClamshell(LidGuard.isClosed, client: type.init()) else { return }
        try? FileManager.default.removeItem(at: marker)
    }
}
