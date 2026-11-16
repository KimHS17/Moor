import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

final class ChargingWhitelistTests: XCTestCase {
    func testPermitsOnlyTwoKeysAndTwoValues() {
        XCTAssertEqual(ChargingWhitelist.keys, [ch0b, ch0c])
        for key in [ch0b, ch0c] {
            XCTAssertTrue(ChargingWhitelist.permits(key: key, bytes: [0x00]))
            XCTAssertTrue(ChargingWhitelist.permits(key: key, bytes: [0x02]))
            XCTAssertFalse(ChargingWhitelist.permits(key: key, bytes: [0x01]))
            XCTAssertFalse(ChargingWhitelist.permits(key: key, bytes: [0x03]))
            XCTAssertFalse(ChargingWhitelist.permits(key: key, bytes: [0xFF]))
        }
    }

    func testRejectsOtherKeys() {
        for name in ["CH0I", "CH0J", "CHTE", "CHIE", "ACLC", "bfF0", "BUIC"] {
            XCTAssertFalse(ChargingWhitelist.permits(key: FourCC(name)!, bytes: [0x00]), name)
        }
    }

    func testRejectsWrongLength() {
        XCTAssertFalse(ChargingWhitelist.permits(key: ch0b, bytes: []))
        XCTAssertFalse(ChargingWhitelist.permits(key: ch0b, bytes: [0x00, 0x00]))
        XCTAssertFalse(ChargingWhitelist.permits(key: ch0b, bytes: [0x02, 0x00, 0x00, 0x00]))
    }

    func testStateClassification() {
        XCTAssertEqual(ChargingState(bytes: [0x00]), .allowed)
        XCTAssertEqual(ChargingState(bytes: [0x02]), .blocked)
        XCTAssertEqual(ChargingState(bytes: [0x01]), .unknown)
        XCTAssertEqual(ChargingState(bytes: []), .unknown)
        XCTAssertEqual(ChargingState(bytes: [0x00, 0x00]), .unknown)
    }
}

final class EnableChargingTests: XCTestCase {
    private var lines: [String] = []

    private func controller(_ smc: FakeSMC) -> ChargingController {
        lines = []
        return ChargingController(smc: smc, log: { [unowned self] in self.lines.append($0) }, sleep: { _ in })
    }

    func testWritesZeroToBothKeysInOrderAndVerifies() throws {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02]])
        try controller(smc).enableCharging()

        XCTAssertEqual(smc.writes.map(\.key), [ch0b, ch0c])
        XCTAssertEqual(smc.writes.map(\.bytes), [[0x00], [0x00]])
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
    }

    func testPrintsCurrentValuesBeforeWriting() throws {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02]])
        try controller(smc).enableCharging()

        XCTAssertEqual(Array(lines.prefix(2)), ["현재 CH0B = 02 (충전 차단)", "현재 CH0C = 02 (충전 차단)"])
        XCTAssertTrue(lines.contains("쓰기 확인 CH0B = 00"))
        XCTAssertTrue(lines.contains("쓰기 확인 CH0C = 00"))
    }

    func testUnknownValueWarnsButProceeds() throws {
        let smc = FakeSMC(["CH0B": [0x01], "CH0C": [0x01]])
        try controller(smc).enableCharging()

        XCTAssertTrue(lines.contains("현재 CH0B = 01 (알 수 없음)"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("경고:") }.count, 2)
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
    }

    func testMissingKeyWritesNothing() {
        let smc = FakeSMC(["CH0B": [0x02]])
        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? SMCError, .keyNotFound(ch0c))
        }
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testUnexpectedSizeWritesNothing() {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02, 0x00, 0x00, 0x00]])
        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .unexpectedDataSize(key: ch0c, size: 4))
        }
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testVerifyMismatchFails() {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02]])
        smc.ignoredWrites = [ch0c]
        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .verifyFailed(key: ch0c, expected: 0x00, observed: [[0x02]]))
        }
    }

    /// 복구 명령이므로 첫 키가 실패해도 두 번째 키는 써야 한다.
    func testFirstKeyFailureStillWritesSecondKey() {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02]])
        smc.failingWrites = [ch0b]
        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? FakeSMCFailure, FakeSMCFailure())
        }
        XCTAssertEqual(smc.writes.map(\.key), [ch0b, ch0c])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
    }
}
