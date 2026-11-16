import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

final class DisableChargingTests: XCTestCase {
    private var lines: [String] = []

    private func controller(_ smc: FakeSMC) -> ChargingController {
        lines = []
        return ChargingController(smc: smc, log: { [unowned self] in self.lines.append($0) })
    }

    func testWritesTwoToBothKeysInOrderAndVerifies() throws {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        try controller(smc).disableCharging()

        XCTAssertEqual(smc.writes.map(\.key), [ch0b, ch0c])
        XCTAssertEqual(smc.writes.map(\.bytes), [[0x02], [0x02]])
        XCTAssertEqual(Array(lines.prefix(2)), ["현재 CH0B = 00 (충전 허용)", "현재 CH0C = 00 (충전 허용)"])
        XCTAssertTrue(lines.contains("쓰기 확인 CH0C = 02"))
    }

    func testUnknownValueWarnsButProceeds() throws {
        let smc = FakeSMC(["CH0B": [0x01], "CH0C": [0x01]])
        try controller(smc).disableCharging()

        XCTAssertEqual(lines.filter { $0.hasPrefix("경고:") }.count, 2)
        XCTAssertEqual(smc.value("CH0B"), [0x02])
        XCTAssertEqual(smc.value("CH0C"), [0x02])
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

    func testSecondKeyWriteFailureRevertsBothToZero() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.failingWrites = [ch0c]
        smc.failingValue = 0x02

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? FakeSMCFailure, FakeSMCFailure())
        }
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
    }

    func testFirstKeyVerifyMismatchSkipsSecondKeyAndReverts() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.ignoredWrites = [ch0b]
        smc.failingValue = 0x02

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .verifyFailed(key: ch0b, expected: 0x02, actual: [0x00]))
        }
        XCTAssertFalse(smc.writes.contains { $0.key == ch0c && $0.bytes == [0x02] })
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
    }

    /// 복구까지 실패해도 원래(차단 쓰기) 오류를 던지고, 복구 실패를 알린다.
    func testRevertFailureStillThrowsOriginalError() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.ignoredWrites = [ch0c]   // CH0B는 02가 되고, CH0C는 어떤 값도 반영되지 않음
        smc.values[ch0c] = [0x01]

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .verifyFailed(key: ch0c, expected: 0x02, actual: [0x01]))
        }
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertTrue(lines.contains { $0.hasPrefix("복구 실패") })
    }
}

final class RunDisableTests: XCTestCase {
    private func makeController(_ smc: FakeSMC) -> ChargingController {
        ChargingController(smc: smc, log: { _ in })
    }

    func testWithoutRevertWritesOnceAndDoesNotWait() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        var waited = false
        let code = runDisable(controller: makeController(smc), revertAfter: nil) { _ in
            waited = true
            return .timeout
        }
        XCTAssertEqual(code, 0)
        XCTAssertFalse(waited)
        XCTAssertEqual(smc.value("CH0B"), [0x02])
        XCTAssertEqual(smc.value("CH0C"), [0x02])
    }

    func testTimeoutRevertsAndExitsZero() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        var seenDuringWait: [UInt8]?
        var requested: Int?
        let code = runDisable(controller: makeController(smc), revertAfter: 60) { seconds in
            requested = seconds
            seenDuringWait = smc.value("CH0B")
            return .timeout
        }
        XCTAssertEqual(code, 0)
        XCTAssertEqual(requested, 60)
        XCTAssertEqual(seenDuringWait, [0x02])
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
    }

    func testSignalRevertsAndExitsWithSignalCode() {
        for (number, expected) in [(SIGINT, Int32(130)), (SIGTERM, Int32(143))] {
            let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
            let code = runDisable(controller: makeController(smc), revertAfter: 60) { _ in .signal(number) }
            XCTAssertEqual(code, expected)
            XCTAssertEqual(smc.value("CH0B"), [0x00])
            XCTAssertEqual(smc.value("CH0C"), [0x00])
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
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        let code = runDisable(controller: makeController(smc), revertAfter: 60) { _ in
            smc.failingWrites = [ch0b]
            return .timeout
        }
        XCTAssertEqual(code, 1)
        XCTAssertEqual(smc.value("CH0C"), [0x00])
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
