import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

final class ChargingWhitelistTests: XCTestCase {
    func testPermitsOnlyTwoKeysAndTwoValues() {
        XCTAssertEqual(ChargingWhitelist.keys, [ch0b, ch0c])
        XCTAssertEqual(ChargingWhitelist.blockKey, ch0b)
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
}

final class PairStateTests: XCTestCase {
    func testKnownPairs() {
        XCTAssertEqual(PairState(b: [0x00], c: [0x00]), .clear)
        XCTAssertEqual(PairState(b: [0x02], c: [0x02]), .blockedByCH0B)
        XCTAssertEqual(PairState(b: [0x01], c: [0x01]), .blockedByCH0C)
        XCTAssertEqual(PairState(b: [0x03], c: [0x03]), .blockedByBoth)
    }

    func testEverythingElseIsUnrecognized() {
        XCTAssertEqual(PairState(b: [0x02], c: [0x00]), .unrecognized)
        XCTAssertEqual(PairState(b: [0x00], c: [0x02]), .unrecognized)
        XCTAssertEqual(PairState(b: [0x03], c: [0x01]), .unrecognized)
        XCTAssertEqual(PairState(b: [0x04], c: [0x04]), .unrecognized)
        XCTAssertEqual(PairState(b: [0xFF], c: [0xFF]), .unrecognized)
        XCTAssertEqual(PairState(b: [], c: []), .unrecognized)
        XCTAssertEqual(PairState(b: [0x00, 0x00], c: [0x00, 0x00]), .unrecognized)
    }

    /// 해석 문구는 키 값만 설명하고 충전 상태를 단정하지 않는다.
    func testLabelsDescribeKeyValuesOnly() {
        let states: [PairState] = [.clear, .blockedByCH0B, .blockedByCH0C, .blockedByBoth, .unrecognized]
        XCTAssertEqual(Set(states.map(\.label)).count, states.count)
        for state in states {
            XCTAssertFalse(state.label.contains("충전 중"), state.label)
            XCTAssertFalse(state.label.contains("충전 허용"), state.label)
            XCTAssertFalse(state.label.contains("충전 안"), state.label)
        }
    }
}

final class EnableChargingTests: XCTestCase {
    private var lines: [String] = []
    private var sleeps: [TimeInterval] = []

    private func controller(_ smc: SMCAccess) -> ChargingController {
        lines = []
        sleeps = []
        return ChargingController(
            smc: smc,
            log: { [unowned self] in self.lines.append($0) },
            sleep: { [unowned self] in self.sleeps.append($0) }
        )
    }

    func testWritesZeroToBothKeysFromEveryKnownState() throws {
        for start: UInt8 in [0x00, 0x01, 0x02, 0x03] {
            let smc = SharedRegisterSMC(register: start)
            try controller(smc).enableCharging()

            XCTAssertEqual(smc.register, 0x00, "start=\(start)")
            XCTAssertEqual(smc.writes.map(\.key), [ch0b, ch0c])
            XCTAssertEqual(smc.writes.map(\.bytes), [[0x00], [0x00]])
        }
    }

    func testOutputInterpretsPairBeforeAndAfter() throws {
        let smc = SharedRegisterSMC(register: 0x03)
        try controller(smc).enableCharging()

        XCTAssertEqual(lines, [
            "현재 CH0B/CH0C = 03/03 (CH0B, CH0C 차단 값 모두 설정됨)",
            "쓰기 CH0B ← 00",
            "쓰기 CH0C ← 00",
            "읽기 변화 CH0B/CH0C: 00/00 (0ms)",
            "최종 CH0B/CH0C = 00/00 (차단 값 없음)",
            "완료: 키 값이 00/00이 됨. 실제 충전 상태는 확인하지 않음. 반영에 수십 초 걸릴 수 있음",
        ])
    }

    /// 한 키만 00으로 쓴 직후의 값(01)은 검증하지 않으므로, 쓰기 사이에는 읽지 않는다.
    func testDoesNotReadBetweenTheTwoWrites() throws {
        let smc = SharedRegisterSMC(register: 0x03)
        try controller(smc).enableCharging()
        // preflight 쌍 읽기 2번 + 최종 쌍 읽기 2번
        XCTAssertEqual(smc.readCount, 4)
    }

    func testPollsUntilPairBecomesZero() throws {
        let smc = SharedRegisterSMC(register: 0x02)
        smc.staleReadsAfterWrite = 4   // 두 번의 쌍 읽기 동안 이전 값이 보임

        try controller(smc).enableCharging()

        XCTAssertTrue(lines.contains("읽기 변화 CH0B/CH0C: 02/02 (0ms) → 00/00 (200ms)"))
        XCTAssertEqual(sleeps.count, 2)
        XCTAssertEqual(sleeps.first ?? 0, 0.1, accuracy: 0.0001)
    }

    func testUnrecognizedStartPairWarnsButProceeds() throws {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x00]])
        try controller(smc).enableCharging()

        XCTAssertTrue(lines.contains("현재 CH0B/CH0C = 02/00 (알려지지 않은 조합)"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("경고:") }.count, 1)
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

    /// 2초 동안 100ms 간격: 쌍 읽기 21번, 대기 20번 뒤 실패한다.
    func testPairNeverReachingZeroFailsAfterTimeout() {
        let smc = SharedRegisterSMC(register: 0x03)
        smc.ignoredWrites = [ch0c]

        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .pairVerifyFailed(expected: 0x00, observed: ["01/01"]))
        }
        XCTAssertEqual(sleeps.count, 20)
        XCTAssertEqual(smc.readCount, 2 + 21 * 2)
        XCTAssertTrue(lines.contains("최종 CH0B/CH0C = 01/01 (CH0C 차단 값만 설정됨)"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("완료") })
    }

    /// 복구 명령이므로 첫 키 쓰기가 실패해도 두 번째 키는 써야 하고, 쓰기 오류를 던진다.
    func testFirstKeyWriteFailureStillWritesSecondKey() {
        let smc = SharedRegisterSMC(register: 0x03)
        smc.failingWrites = [ch0b]

        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? FakeSMCFailure, FakeSMCFailure())
        }
        XCTAssertEqual(smc.writes.map(\.key), [ch0b, ch0c])
        XCTAssertEqual(smc.register, 0x02)
    }

    func testUnrecognizedFinalPairWarns() {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02]])
        smc.settledValueAfterWrite = [ch0b: [0x04], ch0c: [0x04]]

        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .pairVerifyFailed(expected: 0x00, observed: ["04/04"]))
        }
        XCTAssertTrue(lines.contains("최종 CH0B/CH0C = 04/04 (알려지지 않은 조합)"))
        XCTAssertTrue(lines.contains("경고: 04/04은 알려진 조합(00/00, 02/02, 01/01, 03/03)이 아님"))
    }
}
