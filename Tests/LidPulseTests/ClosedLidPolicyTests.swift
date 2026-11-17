import XCTest
@testable import LidPulse

final class ClosedLidPolicyTests: XCTestCase {
    func testTenMinuteLimitOnlyAppliesWhenClosed() {
        let power = PowerStatus(charge: 0.8, onBattery: true)
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: true, elapsed: 599, power: power, thermal: .nominal))
        XCTAssertEqual(ClosedLidPolicy.stopReason(closed: true, elapsed: 600, power: power, thermal: .nominal), .timeout)
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: false, elapsed: 4000, power: power, thermal: .nominal))
    }

    func testLowBatteryAndMissingBatteryReadingStopClosedSession() {
        for charge: Double? in [0.2, 0.01, nil] {
            XCTAssertEqual(ClosedLidPolicy.stopReason(closed: true, elapsed: 1,
                power: .init(charge: charge, onBattery: true), thermal: .nominal), .battery)
        }
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: true, elapsed: 1,
            power: .init(charge: 0.1, onBattery: false), thermal: .nominal))
    }

    func testThermalCutoffAlsoAppliesOnACPower() {
        for thermal in [ProcessInfo.ThermalState.fair, .serious, .critical] {
            XCTAssertEqual(ClosedLidPolicy.stopReason(closed: true, elapsed: 1,
                power: .init(charge: 1, onBattery: false), thermal: thermal), .thermal)
        }
    }
}
