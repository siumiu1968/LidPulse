import XCTest
@testable import LidPulse

final class LogoDriverTests: XCTestCase {
    private var directory: URL!
    private var recovery: URL { directory.appendingPathComponent("original-logo.plist") }
    private let original: [[Double]] = [[0, 0], [100, 80], [1000, 800]]

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testEffectsAndRestoreOnlyWriteTheLogoMapping() throws {
        let client = LogoBrightnessClient(mapping: original)
        let driver = try XCTUnwrap(LogoDriver(client: client, recovery: recovery))
        for nits in [0.0, 25, 100, 400, 1000, 400, 100, 0] {
            XCTAssertTrue(driver.apply(nits: nits))
        }
        XCTAssertTrue(driver.restore())
        XCTAssertEqual(client.mapping, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertEqual(Set(client.writes), [LogoBrightnessClient.mappingKey])
    }

    func testForcedRefreshDoesNotSendADisplayPowerEvent() throws {
        let client = LogoBrightnessClient(mapping: original)
        let driver = try XCTUnwrap(LogoDriver(client: client, recovery: recovery))
        XCTAssertTrue(driver.apply(nits: 100))
        XCTAssertTrue(driver.apply(nits: 100))
        XCTAssertEqual(client.writes.count, 1)
        XCTAssertTrue(driver.apply(nits: 100, force: true))
        XCTAssertEqual(client.writes, Array(repeating: LogoBrightnessClient.mappingKey, count: 2))
        XCTAssertTrue(driver.restore())
    }

    func testRestartRecoveryRestoresOnlyTheSavedLogoMapping() throws {
        try PropertyListEncoder().encode(original).write(to: recovery)
        let client = LogoBrightnessClient(mapping: [[0, 500], [Double(Float.greatestFiniteMagnitude), 500]])
        let driver = try XCTUnwrap(LogoDriver(client: client, recovery: recovery))
        XCTAssertTrue(driver.restore())
        XCTAssertEqual(client.mapping, original)
        XCTAssertEqual(client.writes, [LogoBrightnessClient.mappingKey])
    }

    func testFailedRestoreKeepsRecoveryUntilTheLogoAcceptsIt() throws {
        let client = LogoBrightnessClient(mapping: original)
        let driver = try XCTUnwrap(LogoDriver(client: client, recovery: recovery))
        XCTAssertTrue(driver.apply(nits: 400))
        client.rejectMapping = true
        XCTAssertFalse(driver.restore())
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
        client.rejectMapping = false
        XCTAssertTrue(driver.restore())
        XCTAssertEqual(client.mapping, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
    }

    func testReleasingControlUsesTheOriginalScreenToLogoCurve() {
        XCTAssertEqual(LogoDriver.systemLogoNits(mapping: original, displayNits: 50), 40)
        XCTAssertEqual(LogoDriver.systemLogoNits(mapping: original, displayNits: 550), 440)
        XCTAssertEqual(LogoDriver.systemLogoNits(mapping: original, displayNits: 2000), 800)
        XCTAssertNil(LogoDriver.systemLogoNits(mapping: original, displayNits: .nan))
        XCTAssertNil(LogoDriver.systemLogoNits(mapping: [[0, 1], [0, 2]], displayNits: 10))
    }
}

private final class LogoBrightnessClient: NSObject {
    static let mappingKey = "LEPWMBrightnessNitsMapping"
    var mapping: [[Double]]
    var writes: [String] = []
    var rejectMapping = false

    init(mapping: [[Double]]) { self.mapping = mapping }

    @objc(copyPropertyForKey:)
    func copyProperty(forKey key: NSString) -> AnyObject? {
        key as String == Self.mappingKey ? mapping as NSArray : nil
    }

    @objc(setProperty:forKey:)
    func setProperty(_ value: AnyObject, forKey key: NSString) -> Bool {
        writes.append(key as String)
        // Any attempt to change display power or a system-wide setting fails this boundary.
        guard key as String == Self.mappingKey, !rejectMapping,
              let mapping = value as? [[Double]] else { return false }
        self.mapping = mapping
        return true
    }
}
