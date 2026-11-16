import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

private func described(_ writes: [(key: FourCC, bytes: [UInt8])]) -> [String] {
    writes.map { "\($0.key)=\(hex($0.bytes))" }
}

final class DisableChargingTests: XCTestCase {
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

    func testWritesOnlyCH0BAndConfirmsPair() throws {
        let smc = SharedRegisterSMC()
        try controller(smc).disableCharging()

        XCTAssertEqual(described(smc.writes), ["CH0B=02"])
        XCTAssertEqual(smc.register, 0x02)
        XCTAssertEqual(lines, [
            "현재 CH0B/CH0C = 00/00 (차단 값 없음)",
            "쓰기 CH0B ← 02",
            "읽기 변화 CH0B/CH0C: 02/02 (0ms)",
            "최종 CH0B/CH0C = 02/02 (CH0B 차단 값만 설정됨)",
            "완료: 키 값이 02/02가 됨. 실제 충전 상태는 확인하지 않음. 반영에 수십 초 걸릴 수 있음",
        ])
    }

    func testAlreadyBlockedStaysBlocked() throws {
        let smc = SharedRegisterSMC(register: 0x02)
        try controller(smc).disableCharging()
        XCTAssertEqual(smc.register, 0x02)
    }

    func testPollsUntilPairBecomesTwo() throws {
        let smc = SharedRegisterSMC()
        smc.staleReadsAfterWrite = 6

        try controller(smc).disableCharging()

        XCTAssertTrue(lines.contains("읽기 변화 CH0B/CH0C: 00/00 (0ms) → 02/02 (300ms)"))
        XCTAssertEqual(sleeps.count, 3)
    }

    /// CH0C 쪽 값이 이미 켜져 있으면(01/01) CH0B만 써서는 03/03이 되어 02/02가 되지 않는다.
    /// 실패로 처리하고 두 키를 00으로 되돌린다.
    func testStartingFromCH0CBlockFailsAndRollsBack() {
        let smc = SharedRegisterSMC(register: 0x01)

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .pairVerifyFailed(expected: 0x02, observed: ["03/03"]))
        }
        XCTAssertEqual(described(smc.writes), ["CH0B=02", "CH0B=00", "CH0C=00"])
        XCTAssertEqual(smc.register, 0x00)
        XCTAssertTrue(lines.contains("최종 CH0B/CH0C = 03/03 (CH0B, CH0C 차단 값 모두 설정됨)"))
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("완료") })
    }

    func testWriteFailureRollsBackBothKeys() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.failingWrites = [ch0b]
        smc.failingValue = 0x02

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? FakeSMCFailure, FakeSMCFailure())
        }
        XCTAssertEqual(described(smc.writes), ["CH0B=02", "CH0B=00", "CH0C=00"])
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
    }

    func testVerifyTimeoutRollsBack() {
        let smc = SharedRegisterSMC()
        smc.ignoredWrites = [ch0b]

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .pairVerifyFailed(expected: 0x02, observed: ["00/00"]))
        }
        XCTAssertEqual(sleeps.count, 20)
        XCTAssertEqual(described(smc.writes), ["CH0B=02", "CH0B=00", "CH0C=00"])
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
    }

    /// 복구까지 실패해도 원래(차단 쓰기) 오류를 던지고, 복구 실패를 알린다.
    func testRollbackFailureStillThrowsOriginalError() {
        let smc = SharedRegisterSMC(register: 0x01)
        smc.ignoredWrites = [ch0c]

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .pairVerifyFailed(expected: 0x02, observed: ["03/03"]))
        }
        XCTAssertEqual(smc.register, 0x01)
        XCTAssertTrue(lines.contains { $0.hasPrefix("복구 실패") })
    }

    func testMissingKeyOrWrongSizeWritesNothing() {
        let missing = FakeSMC(["CH0C": [0x00]])
        XCTAssertThrowsError(try controller(missing).disableCharging())
        XCTAssertTrue(missing.writes.isEmpty)

        let wrongSize = FakeSMC(["CH0B": [0x00, 0x00], "CH0C": [0x00]])
        XCTAssertThrowsError(try controller(wrongSize).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .unexpectedDataSize(key: ch0b, size: 2))
        }
        XCTAssertTrue(wrongSize.writes.isEmpty)
    }

    /// disable-charging은 어떤 경로에서도 CH0C에 02를 쓰지 않는다.
    func testNeverWritesTwoToCH0C() {
        for start: UInt8 in [0x00, 0x01, 0x02, 0x03] {
            let smc = SharedRegisterSMC(register: start)
            _ = try? controller(smc).disableCharging()
            XCTAssertFalse(described(smc.writes).contains("CH0C=02"), "start=\(start)")
        }
    }
}

final class RunDisableTests: XCTestCase {
    private func makeController(_ smc: SMCAccess) -> ChargingController {
        ChargingController(smc: smc, log: { _ in }, sleep: { _ in })
    }

    func testWithoutRevertWritesOnceAndDoesNotWait() {
        let smc = SharedRegisterSMC()
        var waited = false
        let code = runDisable(controller: makeController(smc), revertAfter: nil) { _ in
            waited = true
            return .timeout
        }
        XCTAssertEqual(code, 0)
        XCTAssertFalse(waited)
        XCTAssertEqual(smc.register, 0x02)
    }

    func testTimeoutRevertsAndExitsZero() {
        let smc = SharedRegisterSMC()
        var seenDuringWait: UInt8?
        var requested: Int?
        let code = runDisable(controller: makeController(smc), revertAfter: 60) { seconds in
            requested = seconds
            seenDuringWait = smc.register
            return .timeout
        }
        XCTAssertEqual(code, 0)
        XCTAssertEqual(requested, 60)
        XCTAssertEqual(seenDuringWait, 0x02)
        XCTAssertEqual(smc.register, 0x00)
        XCTAssertEqual(described(smc.writes), ["CH0B=02", "CH0B=00", "CH0C=00"])
    }

    func testSignalRevertsAndExitsWithSignalCode() {
        for (number, expected) in [(SIGINT, Int32(130)), (SIGTERM, Int32(143)), (SIGHUP, Int32(129))] {
            let smc = SharedRegisterSMC()
            let code = runDisable(controller: makeController(smc), revertAfter: 60) { _ in .signal(number) }
            XCTAssertEqual(code, expected)
            XCTAssertEqual(smc.register, 0x00)
        }
    }

    func testDisableFailureDoesNotWait() {
        let smc = FakeSMC(["CH0B": [0x00]])
        var waited = false
        let code = runDisable(controller: makeController(smc), revertAfter: 60) { _ in
            waited = true
            return .timeout
        }
        XCTAssertEqual(code, 1)
        XCTAssertFalse(waited)
    }

    func testRevertFailureExitsOne() {
        let smc = SharedRegisterSMC()
        let code = runDisable(controller: makeController(smc), revertAfter: 60) { _ in
            smc.failingWrites = [ch0b]
            return .timeout
        }
        XCTAssertEqual(code, 1)
        XCTAssertEqual(smc.register, 0x02)
    }
}

final class SignalWaiterTests: XCTestCase {
    func testTimesOutWithoutSignal() {
        XCTAssertEqual(SignalWaiter().wait(seconds: 1), .timeout)
    }

    /// `wait`를 부르기 전에 받은 시그널도 놓치지 않는다.
    func testReportsSignalReceivedBeforeWait() {
        let waiter = SignalWaiter()
        kill(getpid(), SIGTERM)
        XCTAssertEqual(waiter.wait(seconds: 5), .signal(SIGTERM))
    }
}

final class DisableCommandTests: XCTestCase {
    func testParsesDisableCharging() {
        XCTAssertEqual(Command.parse(["disable-charging"]), .success(.disableCharging(revertAfter: nil)))
        XCTAssertEqual(
            Command.parse(["disable-charging", "--revert-after", "60"]),
            .success(.disableCharging(revertAfter: 60))
        )
        XCTAssertEqual(
            Command.parse(["disable-charging", "--revert-after", "86400"]),
            .success(.disableCharging(revertAfter: 86_400))
        )
    }

    func testRejectsInvalidRevertAfter() {
        let invalid: [[String]] = [
            ["--revert-after"], ["--revert-after", "0"], ["--revert-after", "-5"],
            ["--revert-after", "abc"], ["--revert-after", "1.5"], ["--revert-after", "86401"],
            ["--revert-after", "60", "extra"], ["--force"], ["60"],
        ]
        for arguments in invalid {
            XCTAssertThrowsError(try Command.parse(["disable-charging"] + arguments).get(), "\(arguments)")
        }
    }

    func testRequiresRoot() {
        XCTAssertTrue(Command.disableCharging(revertAfter: nil).requiresRoot)
        XCTAssertTrue(Command.disableCharging(revertAfter: 60).requiresRoot)
    }
}
