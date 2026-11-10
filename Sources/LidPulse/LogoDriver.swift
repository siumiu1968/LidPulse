import Foundation
import IOKit
import ObjectiveC
import Darwin

final class LogoDriver {
    private static let mappingKey = "LEPWMBrightnessNitsMapping"
    private static let mappingMax = Double(Float.greatestFiniteMagnitude)
    private static let factorFadeKey = "LEPWMFactorFadeDuration"
    private let client: NSObject
    private let copy = NSSelectorFromString("copyPropertyForKey:")
    private let set = NSSelectorFromString("setProperty:forKey:")
    private let recovery: URL
    private var original: [[Double]]?
    private var last: Double?
    private lazy var closedLid = ClosedLidLogo()
    private var attemptedOpeningFade = false
    private var ownsOpeningFade = false
    private var openingFadeReset: DispatchWorkItem?
    private var openingFadeRecovery: URL { recovery.appendingPathExtension("opening-fade") }

    private typealias Setter = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Bool

    init?(recovery: URL) {
        let node = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pwm1/bklb-backlight")
        guard node != 0 else { return nil }
        IOObjectRelease(node)
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL) != nil,
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type else { return nil }
        let client = type.init()
        guard client.responds(to: copy), client.responds(to: set) else { return nil }
        self.client = client
        self.recovery = recovery
        guard readMapping() != nil else { return nil }
    }

    private func readMapping() -> [[Double]]? {
        guard let mapping = client.perform(copy, with: Self.mappingKey)?.takeRetainedValue() as? [[Double]],
              Self.valid(mapping) else { return nil }
        return mapping
    }

    var hasFullRange: Bool {
        let key = "LEPWMLuxToMaxNitsRestrictionMapping"
        guard let mapping = client.perform(copy, with: key)?.takeRetainedValue() as? [[Double]],
              Self.valid(mapping) else { return false }
        return mapping.allSatisfy { $0[1] >= 999 }
    }

    var supportsClosedLid: Bool { closedLid != nil }
    var isLidClosed: Bool { closedLid?.isClosed == true }
    var needsClosedLidHandoff: Bool { closedLid?.needsHandoff == true }

    func applyWithLidClosed(nits: Double) -> Bool {
        guard nits.isFinite, let closedLid else { return false }
        let applied = closedLid.apply(nits: nits) {
            client.perform(copy, with: "LEPWMState")?.takeRetainedValue() as? [String: Double]
        }
        if applied, closedLid.isDrivingLight { prepareOpeningFade() }
        return applied
    }

    func releaseClosedLid() {
        if closedLid?.release() == true { last = nil }
        attemptedOpeningFade = false
        guard ownsOpeningFade else { return }
        if closedLid?.isClosed == true {
            restoreOpeningFade()
        } else if openingFadeReset == nil {
            // The lid notification can arrive before CoreBrightness starts its ramp.
            let reset = DispatchWorkItem { [weak self] in self?.restoreOpeningFade() }
            openingFadeReset = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: reset)
        }
    }

    private func prepareOpeningFade() {
        openingFadeReset?.cancel()
        openingFadeReset = nil
        guard !ownsOpeningFade, !attemptedOpeningFade else { return }
        attemptedOpeningFade = true
        let current = client.perform(copy, with: Self.factorFadeKey)?.takeRetainedValue() as? NSNumber
        guard (current?.doubleValue ?? 0) == 0 else { return }
        do {
            try FileManager.default.createDirectory(at: recovery.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: openingFadeRecovery, options: .atomic)
        } catch { return }
        // Zero selects the system default. A positive duration shorter than the first
        // sample makes the native ramp start directly at the requested brightness.
        ownsOpeningFade = write(0.000_000_001 as NSNumber, key: Self.factorFadeKey)
        if !ownsOpeningFade { try? FileManager.default.removeItem(at: openingFadeRecovery) }
    }

    func restoreOpeningFade() {
        openingFadeReset?.cancel()
        openingFadeReset = nil
        guard ownsOpeningFade || FileManager.default.fileExists(atPath: openingFadeRecovery.path),
              write(0 as NSNumber, key: Self.factorFadeKey) else { return }
        ownsOpeningFade = false
        try? FileManager.default.removeItem(at: openingFadeRecovery)
    }

    // A flat two-point curve indicates a manual logo override. Do not
    // take over an existing override from another controller.
    var hasOtherOverride: Bool {
        guard let mapping = readMapping(), mapping.count == 2,
              mapping[0][0] == 0, mapping[1][0] > 1e30,
              abs(mapping[0][1] - mapping[1][1]) < 0.01 else { return false }
        if let last { return abs(mapping[0][1] - last) >= 0.01 }
        return !recoveryExists
    }

    private static func valid(_ mapping: [[Double]]) -> Bool {
        mapping.count >= 2 && mapping.count <= 512 && mapping.allSatisfy {
            $0.count == 2 && $0.allSatisfy { $0.isFinite && $0 >= 0 }
        }
    }

    private func write(_ value: AnyObject, key: String) -> Bool {
        guard let imp = client.method(for: set) else { return false }
        return unsafeBitCast(imp, to: Setter.self)(client, set, value, key as NSString)
    }

    private func writeMapping(_ mapping: [[Double]]) -> Bool {
        write(mapping as NSArray, key: Self.mappingKey) &&
            write(1 as NSNumber, key: "DisplayPowerStateEvent")
    }

    private var recoveryExists: Bool { FileManager.default.fileExists(atPath: recovery.path) }

    func apply(nits: Double, force: Bool = false) -> Bool {
        guard nits.isFinite else { return false }
        releaseClosedLid()
        let value = min(1000, max(0, nits))
        if !force, let last, abs(value - last) < 0.45, value != 0 || last == 0 { return true }

        if original == nil {
            if recoveryExists, !restore() { return false }
            guard let saved = readMapping() else { return false }
            do {
                try FileManager.default.createDirectory(at: recovery.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try PropertyListEncoder().encode(saved)
                try data.write(to: recovery, options: .atomic)
                original = saved
            } catch { return false }
        }
        guard writeMapping([[0, value], [Self.mappingMax, value]]) else { return false }
        last = value
        return true
    }

    @discardableResult
    func restore() -> Bool {
        if !ownsOpeningFade { restoreOpeningFade() }
        releaseClosedLid()
        guard original != nil || recoveryExists else { return true }
        let saved = original ?? (try? PropertyListDecoder().decode([[Double]].self, from: Data(contentsOf: recovery)))
        guard let saved, Self.valid(saved),
              writeMapping(saved), let actual = readMapping(),
              actual.count == saved.count,
              zip(actual, saved).allSatisfy({ pair in
                  zip(pair.0, pair.1).allSatisfy { abs($0.0 - $0.1) <= max(0.001, abs($0.1) * 1e-6) }
              }) else { return false }
        last = nil
        original = nil
        if recoveryExists {
            do { try FileManager.default.removeItem(at: recovery) }
            catch { return false }
        }
        return true
    }

    static func dutyCycle() -> Double? {
        let node = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pwm1/bklb-backlight")
        guard node != 0 else { return nil }
        defer { IOObjectRelease(node) }
        func property(_ key: String) -> NSNumber? {
            IORegistryEntryCreateCFProperty(node, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
        }
        guard let high = property("high-period")?.doubleValue,
              let low = property("low-period")?.doubleValue, high + low > 0 else { return nil }
        return property("enabled")?.boolValue == true ? high / (high + low) : 0
    }
}
