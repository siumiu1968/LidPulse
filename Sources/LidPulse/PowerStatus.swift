import Foundation
import IOKit.ps

struct PowerStatus {
    let charge: Double?
    let onBattery: Bool

    static func read() -> Self {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .init(charge: nil, onBattery: true)
        }
        let onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = values[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = values[kIOPSMaxCapacityKey] as? NSNumber, maximum.doubleValue > 0 else { continue }
            return .init(charge: min(1, max(0, current.doubleValue / maximum.doubleValue)), onBattery: onBattery)
        }
        return .init(charge: nil, onBattery: onBattery)
    }
}

enum ClosedLidPolicy {
    static let maximumDuration: TimeInterval = 30 * 60
    enum Stop: Int32 { case timeout = 2, battery = 3, thermal = 4, unavailable = 5 }

    static func stopReason(closed: Bool, elapsed: TimeInterval, power: PowerStatus,
                           thermal: ProcessInfo.ThermalState) -> Stop? {
        guard closed else { return nil }
        if thermal == .serious || thermal == .critical { return .thermal }
        if power.onBattery, power.charge.map({ $0 < 0.20 }) ?? true { return .battery }
        if elapsed >= maximumDuration { return .timeout }
        return nil
    }
}
