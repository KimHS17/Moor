import XCTest
@testable import MoorCore

final class BatteryInfoTests: XCTestCase {
    func testParsesProperties() {
        let info = BatteryInfo(properties: [
            "CurrentCapacity": 55, "IsCharging": true, "ExternalConnected": true,
            "CycleCount": 123, "Temperature": 3050,
        ])
        XCTAssertEqual(info, BatteryInfo(percent: 55, isCharging: true, isPluggedIn: true, cycleCount: 123, temperatureCelsius: 30.5))
    }

    func testMissingRequiredKeyReturnsNil() {
        XCTAssertNil(BatteryInfo(properties: ["CurrentCapacity": 55, "CycleCount": 1]))
    }

    func testPercentIsClamped() {
        let info = BatteryInfo(properties: ["CurrentCapacity": 140, "CycleCount": 1, "Temperature": 3000])
        XCTAssertEqual(info?.percent, 100)
    }

    func testOptionalFlagsDefaultToFalse() {
        let info = BatteryInfo(properties: ["CurrentCapacity": 10, "CycleCount": 1, "Temperature": 3000])
        XCTAssertEqual(info?.isCharging, false)
        XCTAssertEqual(info?.isPluggedIn, false)
    }
}
