import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

final class PollingVerifyTests: XCTestCase {
    private var lines: [String] = []
    private var sleeps: [TimeInterval] = []

    private func controller(_ smc: FakeSMC) -> ChargingController {
        lines = []
        sleeps = []
        return ChargingController(
            smc: smc,
            log: { [unowned self] in self.lines.append($0) },
            sleep: { [unowned self] in self.sleeps.append($0) }
        )
    }

    /// 실측에서 본 상황: CH0C에 02를 쓴 직후 03으로 읽히다가 02가 된다.
    func testTransientValueSettlesWithinTimeout() throws {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.transientReadsAfterWrite = [ch0c: [[0x03], [0x03], [0x03]]]

        try controller(smc).disableCharging()

        XCTAssertTrue(lines.contains("읽기 변화 CH0C: 03 (0ms) → 02 (300ms)"))
        XCTAssertTrue(lines.contains("쓰기 확인 CH0C = 02"))
        XCTAssertTrue(lines.contains("완료: 충전 차단(02)으로 설정함"))
        XCTAssertEqual(smc.value("CH0B"), [0x02])
        XCTAssertEqual(smc.value("CH0C"), [0x02])
    }

    func testImmediateMatchReadsOnceWithoutSleeping() throws {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        try controller(smc).writeAndVerify(ch0b, .block)

        XCTAssertTrue(sleeps.isEmpty)
        XCTAssertEqual(smc.readCounts[ch0b], 1)
        XCTAssertTrue(lines.contains("읽기 변화 CH0B: 02 (0ms)"))
    }

    func testPrintsEveryChangeInOrder() throws {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x02]])
        smc.transientReadsAfterWrite = [ch0b: [[0x03], [0x01], [0x01], [0x03]]]

        try controller(smc).writeAndVerify(ch0b, .allow)

        XCTAssertTrue(lines.contains("읽기 변화 CH0B: 03 (0ms) → 01 (100ms) → 03 (300ms) → 00 (400ms)"))
    }

    /// 2초 동안 100ms 간격: 읽기 21번, 대기 20번 뒤 실패한다.
    func testNeverMatchingFailsAfterTimeout() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.settledValueAfterWrite = [ch0b: [0x03]]

        XCTAssertThrowsError(try controller(smc).writeAndVerify(ch0b, .block)) {
            XCTAssertEqual($0 as? ChargingError, .verifyFailed(key: ch0b, expected: 0x02, observed: [[0x03]]))
        }
        XCTAssertEqual(smc.readCounts[ch0b], 21)
        XCTAssertEqual(sleeps.count, 20)
        XCTAssertEqual(sleeps.first ?? 0, 0.1, accuracy: 0.0001)
        XCTAssertTrue(lines.contains("읽기 변화 CH0B: 03 (0ms)"))
        XCTAssertTrue(lines.contains("CH0B: 2000ms 동안 02이 되지 않음"))
    }

    func testMatchOnLastAttemptSucceeds() throws {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.transientReadsAfterWrite = [ch0b: Array(repeating: [0x03], count: 20)]

        try controller(smc).writeAndVerify(ch0b, .block)

        XCTAssertEqual(smc.readCounts[ch0b], 21)
        XCTAssertTrue(lines.contains("읽기 변화 CH0B: 03 (0ms) → 02 (2000ms)"))
    }

    /// 끝까지 맞지 않으면 차단은 실패하고, 두 키를 00으로 되돌린다(롤백도 폴링으로 검증).
    func testNeverSettlingBlockRollsBack() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.failingValue = 0x02
        smc.ignoredWrites = [ch0c]
        smc.transientReadsAfterWrite = [ch0b: [[0x01], [0x01]]]

        XCTAssertThrowsError(try controller(smc).disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .verifyFailed(key: ch0c, expected: 0x02, observed: [[0x00]]))
        }
        XCTAssertTrue(lines.contains("읽기 변화 CH0B/CH0C: 01/00 (0ms) → 00/00 (200ms)"))
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
    }

    /// 두 번째 키를 쓰는 동안 첫 번째 키가 다른 값으로 바뀌어 돌아오지 않으면 최종 확인에서 실패한다.
    func testFinalConfirmationCatchesFirstKeyChangedLater() {
        let smc = DriftingSMC(["CH0B": [0x00], "CH0C": [0x00]])
        let controller = ChargingController(smc: smc, log: { [unowned self] in self.lines.append($0) }, sleep: { _ in })
        lines = []

        XCTAssertThrowsError(try controller.disableCharging()) {
            XCTAssertEqual($0 as? ChargingError, .pairVerifyFailed(expected: 0x02, observed: ["03/02"]))
        }
        XCTAssertFalse(lines.contains("완료: 충전 차단(02)으로 설정함"))
    }
}

/// CH0C에 02를 쓰면 CH0B가 03으로 바뀌는 가짜 SMC.
private final class DriftingSMC: SMCAccess {
    private let inner: FakeSMC

    init(_ values: [String: [UInt8]]) { inner = FakeSMC(values) }

    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo { try inner.keyInfo(key) }
    func read(_ key: FourCC) throws -> SMCValue { try inner.read(key) }
    func write(_ key: FourCC, bytes: [UInt8]) throws {
        try inner.write(key, bytes: bytes)
        if key == ch0c && bytes == [0x02] { inner.values[ch0b] = [0x03] }
    }
}

final class WatchTests: XCTestCase {
    func testParsesWatch() {
        XCTAssertEqual(Command.parse(["watch", "--seconds", "10"]), .success(.watch(seconds: 10)))
        XCTAssertFalse(Command.watch(seconds: 10).requiresRoot)
    }

    func testRejectsInvalidWatchArguments() {
        let invalid: [[String]] = [
            [], ["--seconds"], ["--seconds", "0"], ["--seconds", "-1"], ["--seconds", "abc"],
            ["--seconds", "3601"], ["10"], ["--seconds", "10", "CH0I"],
        ]
        for arguments in invalid {
            XCTAssertThrowsError(try Command.parse(["watch"] + arguments).get(), "\(arguments)")
        }
    }

    func testLineFormat() {
        XCTAssertEqual(
            Watch.line(timestamp: "14:03:07.200", readings: [(ch0b, "02"), (ch0c, "03")]),
            "14:03:07.200  CH0B=02  CH0C=03"
        )
    }

    func testTimestampHasMilliseconds() {
        let stamp = Watch.timestamp(Date(timeIntervalSince1970: 0.25))
        XCTAssertNotNil(stamp.range(of: #"^\d{2}:\d{2}:\d{2}\.250$"#, options: .regularExpression), stamp)
    }

    /// 1초면 0ms부터 1000ms까지 200ms 간격으로 6번 읽고, 쓰기는 하지 않는다.
    func testSamplesEvery200msAndNeverWrites() {
        let smc = FakeSMC(["CH0B": [0x02], "CH0C": [0x03]])
        var lines: [String] = []
        var sleeps: [TimeInterval] = []
        let code = Watch.run(
            smc: smc, seconds: 1,
            now: { Date(timeIntervalSince1970: 0) },
            sleep: { sleeps.append($0) },
            log: { lines.append($0) }
        )

        XCTAssertEqual(code, 0)
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(sleeps.count, 5)
        XCTAssertEqual(sleeps.first ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertTrue(lines.allSatisfy { $0.hasSuffix("  CH0B=02  CH0C=03") })
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testReadErrorIsShownAndExitsOne() {
        let smc = FakeSMC(["CH0B": [0x00]])
        var lines: [String] = []
        let code = Watch.run(smc: smc, seconds: 1, sleep: { _ in }, log: { lines.append($0) })

        XCTAssertEqual(code, 1)
        XCTAssertEqual(lines.count, 6)
        XCTAssertTrue(lines[0].contains("CH0B=00"))
        XCTAssertTrue(lines[0].contains("CH0C=오류("))
    }
}
