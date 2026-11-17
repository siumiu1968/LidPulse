import XCTest
@testable import LidPulse

final class ClosedLidPolicyTests: XCTestCase {
    func testThirtyMinuteLimitOnlyAppliesWhenClosed() {
        let power = PowerStatus(charge: 0.8, onBattery: true)
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: true, elapsed: 600, power: power, thermal: .nominal))
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: true, elapsed: 1799, power: power, thermal: .nominal))
        XCTAssertEqual(ClosedLidPolicy.stopReason(closed: true, elapsed: 1800, power: power, thermal: .nominal), .timeout)
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: false, elapsed: 4000, power: power, thermal: .nominal))
    }

    func testLowBatteryAndMissingBatteryReadingStopClosedSession() {
        for charge: Double? in [0.199, 0.01, nil] {
            XCTAssertEqual(ClosedLidPolicy.stopReason(closed: true, elapsed: 1,
                power: .init(charge: charge, onBattery: true), thermal: .nominal), .battery)
        }
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: true, elapsed: 1,
            power: .init(charge: 0.2, onBattery: true), thermal: .nominal))
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: true, elapsed: 1,
            power: .init(charge: 0.1, onBattery: false), thermal: .nominal))
    }

    func testThermalCutoffAlsoAppliesOnACPower() {
        for thermal in [ProcessInfo.ThermalState.serious, .critical] {
            XCTAssertEqual(ClosedLidPolicy.stopReason(closed: true, elapsed: 1,
                power: .init(charge: 1, onBattery: false), thermal: thermal), .thermal)
        }
    }

    func testFairThermalPressureDoesNotStopSession() {
        XCTAssertNil(ClosedLidPolicy.stopReason(closed: true, elapsed: 1200,
            power: .init(charge: 0.8, onBattery: true), thermal: .fair))
    }
}
