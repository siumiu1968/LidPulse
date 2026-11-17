import Foundation
import IOKit
import ObjectiveC
import os

/// Uses the lid LED's own controller to hold a steady level while the display sleeps.
final class ClosedLidStaticLogo {
    private typealias Allocate = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
    private typealias InitDevice = @convention(c) (AnyObject, Selector, io_service_t) -> Unmanaged<AnyObject>?
    private typealias InitCalibration = @convention(c) (AnyObject, Selector, io_service_t, AnyObject) -> Unmanaged<AnyObject>?
    private typealias SetFloat = @convention(c) (AnyObject, Selector, Float) -> Void
    private typealias ReadInteger = @convention(c) (AnyObject, Selector) -> UInt64
    private typealias Convert = @convention(c) (AnyObject, Selector, Float) -> Float
    private typealias EnablePulse = @convention(c) (AnyObject, Selector) -> Void

    private static let pulseSelector = NSSelectorFromString("enablePulseRoutine")
    private static let conversionSelector = NSSelectorFromString("convertNitsToPWMPercentage:")
    private let led: io_registry_entry_t
    private let power: io_service_t
    private let pwm: AnyObject
    private let calibration: AnyObject
    private let pulse: EnablePulse
    private let convert: Convert
    private let minimum: UInt64
    private let maximum: UInt64
    private let frequency: UInt64
    private let period: UInt64
    private var lastDuty: UInt64?
    private var lastRequest: Double?
    private static let dutyLimit = UInt64(1) << 32
    private static var marker: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LidPulse/static-lid-override")
    }

    init?() {
        let led = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pwm1/bklb-backlight")
        let power = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        var initialized = false
        defer {
            if !initialized {
                if led != 0 { IOObjectRelease(led) }
                if power != 0 { IOObjectRelease(power) }
            }
        }
        guard led != 0, power != 0, IOObjectConformsTo(led, "AppleARMPWMDevice") != 0,
              Self.number(power, "AppleClamshellState") != nil,
              let clock = Self.number(led, "pwm-frequency")?.uint64Value, clock == 24_000_000,
              let pwmType = NSClassFromString("PWMDeviceController"),
              let calibrationType = NSClassFromString("PWMCalibrationManager"),
              let configType = NSClassFromString("PWMConfiguration") as? NSObject.Type,
              let pulse = Self.method(pwmType, Self.pulseSelector, "v16@0:8"),
              let convert = Self.method(calibrationType, Self.conversionSelector, "f20@0:8f16")
        else { return nil }

        let deviceInit = NSSelectorFromString("initWithService:")
        let calibrationInit = NSSelectorFromString("initWithDevice:configuration:")
        guard let initDevice = Self.method(pwmType, deviceInit, "@20@0:8I16"),
              let initCalibration = Self.method(calibrationType, calibrationInit, "@28@0:8I16@20"),
              let device = Self.allocate(pwmType) else { return nil }
        guard let pwm = unsafeBitCast(initDevice, to: InitDevice.self)(device.takeUnretainedValue(), deviceInit, led)?.takeRetainedValue(),
              let minimum = Self.integer(pwm, "hwMinPwm"),
              let maximum = Self.integer(pwm, "hwMaxPwm"), minimum < maximum, maximum < Self.dutyLimit,
              let frequency = Self.integer(pwm, "frequency"), (10_000...100_000).contains(frequency)
        else { return nil }

        let config = configType.init()
        let nodeName = NSSelectorFromString("setNodeName:")
        guard config.responds(to: nodeName) else { return nil }
        _ = config.perform(nodeName, with: "bklb-backlight" as NSString)
        // Match the native lid driver; the calibration manager loads the device's own curves.
        let settings: [(String, Float)] = [
            ("setMinPercentage:", 0.01), ("setMaxPercentage:", 100),
            ("setMinNits:", 0.01), ("setMaxNits:", 1500)
        ]
        for (name, value) in settings {
            let selector = NSSelectorFromString(name)
            guard let imp = Self.method(configType, selector, "v20@0:8f16") else { return nil }
            unsafeBitCast(imp, to: SetFloat.self)(config, selector, value)
        }
        guard let calibrator = Self.allocate(calibrationType),
              let calibration = unsafeBitCast(initCalibration, to: InitCalibration.self)(
                calibrator.takeUnretainedValue(), calibrationInit, led, config
              )?.takeRetainedValue() else { return nil }

        self.led = led
        self.power = power
        self.pwm = pwm
        self.calibration = calibration
        self.pulse = unsafeBitCast(pulse, to: EnablePulse.self)
        self.convert = unsafeBitCast(convert, to: Convert.self)
        self.minimum = minimum
        self.maximum = maximum
        self.frequency = frequency
        period = clock / frequency
        initialized = true
    }

    deinit {
        IOObjectRelease(led)
        IOObjectRelease(power)
    }

    var isClosed: Bool { Self.number(power, "AppleClamshellState")?.boolValue == true }
    var isDrivingLight: Bool { (lastDuty ?? 0) > 0 }

    var needsHandoff: Bool {
        lastDuty != 0 && Self.number(led, "enabled")?.boolValue == false
    }

    func apply(nits: Double, restrictions: () -> [String: Double]?) -> Bool {
        guard isClosed else { return true }
        guard let enabled = Self.number(led, "enabled")?.boolValue else { return false }
        if lastRequest == nits, let lastDuty, hardwareMatches(lastDuty, enabled: enabled) { return true }
        // Take over as soon as macOS releases the LED.
        if lastDuty == nil, enabled, nits > 0 { return true }

        var limitedNits = 0.0
        if nits > 0 {
            guard let restrictions = restrictions(),
                  let minNits = restrictions["MinNitsRestriction"], let maxNits = restrictions["MaxNitsRestriction"],
                  let multiplier = restrictions["NitsMultiplier"],
                  minNits.isFinite, maxNits.isFinite, minNits >= 0, minNits <= maxNits,
                  multiplier.isFinite, (0...1).contains(multiplier) else {
                release()
                return false
            }
            limitedNits = min(1000, maxNits, max(minNits, nits)) * multiplier
        }
        let percentage = convert(calibration, Self.conversionSelector, Float(limitedNits))
        guard percentage.isFinite, (0...100).contains(percentage) else { return false }
        if lastDuty == nil {
            Logger(subsystem: "local.lidpulse", category: "static-logo")
                .info("Static LED requested=\(nits) limited=\(limitedNits) percentage=\(percentage)")
        }
        let duty = limitedNits > 0 && percentage > 0
            ? min(maximum, UInt64(Float(minimum) + percentage * Float(maximum - minimum) / 100))
            : 0
        if lastDuty == duty, hardwareMatches(duty, enabled: enabled) { lastRequest = nits; return true }
        guard isClosed else { return true }
        if lastDuty == nil {
            do {
                try FileManager.default.createDirectory(at: Self.marker.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: Self.marker, options: .atomic)
            } catch { return false }
        }
        if duty != 0, !enabled { pulse(pwm, Self.pulseSelector) }
        guard write(duty) else {
            _ = write(0)
            lastDuty = nil
            return false
        }
        lastDuty = duty
        lastRequest = nits
        return true
    }

    private func hardwareMatches(_ duty: UInt64, enabled: Bool) -> Bool {
        guard enabled == (duty != 0) else { return false }
        if !enabled { return true }
        let high = Self.number(led, "high-period")?.doubleValue
        let expected = Double(duty) * Double(period) / Double(Self.dutyLimit)
        return high.map { abs($0 - expected) <= 1 } == true
    }

    /// Returns whether the normal driver needs to refresh its output on opening.
    @discardableResult
    func release() -> Bool {
        guard let lastDuty else { return false }
        if isClosed, lastDuty != 0, !write(0) { return false }
        self.lastDuty = nil
        lastRequest = nil
        try? FileManager.default.removeItem(at: Self.marker)
        return true
    }

    static func recoverAfterExit() {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        if LidGuard.isClosed {
            let node = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pwm1/bklb-backlight")
            guard node != 0 else { return }
            defer { IOObjectRelease(node) }
            guard IOObjectConformsTo(node, "AppleARMPWMDevice") != 0,
                  IORegistryEntrySetCFProperties(node, ["set-duty-cycle": 0, "set-enabled": false] as CFDictionary) == KERN_SUCCESS
            else { return }
        }
        try? FileManager.default.removeItem(at: marker)
    }

    private func write(_ duty: UInt64) -> Bool {
        IORegistryEntrySetCFProperties(led, [
            "set-duty-cycle": NSNumber(value: duty),
            "set-hz": NSNumber(value: frequency),
            "set-enabled": NSNumber(value: duty != 0)
        ] as CFDictionary) == KERN_SUCCESS
    }

    private static func number(_ node: io_registry_entry_t, _ key: String) -> NSNumber? {
        IORegistryEntryCreateCFProperty(node, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
    }

    private static func method(_ type: AnyClass, _ selector: Selector, _ signature: String) -> IMP? {
        guard let method = class_getInstanceMethod(type, selector),
              let encoding = method_getTypeEncoding(method), String(cString: encoding) == signature else { return nil }
        return method_getImplementation(method)
    }

    private static func allocate(_ type: AnyClass) -> Unmanaged<AnyObject>? {
        let selector = NSSelectorFromString("alloc")
        guard let method = class_getClassMethod(type, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: Allocate.self)(type, selector)
    }

    private static func integer(_ object: AnyObject, _ name: String) -> UInt64? {
        let selector = NSSelectorFromString(name)
        guard let type = object_getClass(object), let imp = method(type, selector, "Q16@0:8") else { return nil }
        return unsafeBitCast(imp, to: ReadInteger.self)(object, selector)
    }
}
