import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

/// 실측 동작(두 키가 같은 값, 한 키만 00으로 쓰면 01이 남음)에서 복구가 오보 없이 끝나는지 본다.
final class PairRestoreTests: XCTestCase {
    private var lines: [String] = []

    private func controller(_ smc: SMCAccess) -> ChargingController {
        lines = []
        return ChargingController(smc: smc, log: { [unowned self] in self.lines.append($0) }, sleep: { _ in })
    }

    func testEnableFromThreeWritesBothThenVerifiesPair() throws {
        let smc = SharedRegisterSMC(register: 0x03)
        try controller(smc).enableCharging()

        XCTAssertEqual(smc.register, 0x00)
        XCTAssertEqual(smc.writes.map(\.key), [ch0b, ch0c])
        XCTAssertTrue(lines.contains("읽기 변화 CH0B/CH0C: 00/00 (0ms)"))
        XCTAssertTrue(lines.contains("최종 확인: CH0B/CH0C = 00/00"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("오류") })
    }

    func testEnableFromOneAndFromTwo() throws {
        for start: UInt8 in [0x01, 0x02] {
            let smc = SharedRegisterSMC(register: start)
            try controller(smc).enableCharging()
            XCTAssertEqual(smc.register, 0x00)
        }
    }

    /// 현재 disable-charging은 실측대로 CH0C 검증(03)에서 실패한다. 그 뒤 롤백은 00/00으로 끝나야 한다.
    func testDisableStillFailsOnHardwareModelButRollbackSucceeds() {
        let smc = SharedRegisterSMC()
        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .verifyFailed(key: ch0c, expected: 0x02, observed: [[0x03]]))
        }
        XCTAssertEqual(smc.register, 0x00)
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("복구 실패") })
    }

    func testPairNeverReachingZeroFails() {
        let smc = SharedRegisterSMC(register: 0x03)
        smc.failingWrites = [ch0c]
        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? FakeSMCFailure, FakeSMCFailure())
        }
        XCTAssertEqual(smc.register, 0x01)
        XCTAssertFalse(lines.contains("완료: 충전 허용(00)으로 설정함"))
    }

    func testPairVerifyFailureWithoutWriteErrorReportsObservedPairs() {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02]])
        smc.settledValueAfterWrite = [ch0b: [0x01], ch0c: [0x01]]
        XCTAssertThrowsError(try controller(smc).enableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .pairVerifyFailed(expected: 0x00, observed: ["01/01"]))
        }
    }
}
