import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

final class SetCommandTests: XCTestCase {
    private func plan(_ arguments: String...) throws -> SetPlan {
        guard case .set(let plan) = try Command.parse(["set"] + arguments).get() else {
            XCTFail("set이 아님")
            throw UsageError(message: "")
        }
        return plan
    }

    func testParsesValuesOrderAndHold() throws {
        XCTAssertEqual(try plan("02", "02", "--hold", "10"), SetPlan(b: .block, c: .block, order: .bc, holdSeconds: 10))
        XCTAssertEqual(try plan("02", "-", "--hold", "120"), SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 120))
        XCTAssertEqual(
            try plan("00", "02", "--order", "cb", "--hold", "1"),
            SetPlan(b: .allow, c: .block, order: .cb, holdSeconds: 1)
        )
        XCTAssertEqual(
            try plan("02", "00", "--hold", "5", "--order", "bc"),
            SetPlan(b: .block, c: .allow, order: .bc, holdSeconds: 5)
        )
    }

    func testRejectsInvalidArguments() {
        let invalid: [[String]] = [
            [], ["02"], ["02", "02"],                              // --hold 필수
            ["01", "02", "--hold", "5"], ["02", "03", "--hold", "5"],
            ["2", "02", "--hold", "5"], ["0x02", "02", "--hold", "5"],
            ["-", "02", "--hold", "5"],                            // B는 생략할 수 없음
            ["02", "02", "--hold", "0"], ["02", "02", "--hold", "121"], ["02", "02", "--hold", "abc"],
            ["02", "02", "--hold"], ["02", "02", "--hold", "5", "--hold", "6"],
            ["02", "02", "--order", "bb", "--hold", "5"], ["02", "02", "--order", "--hold", "5"],
            ["02", "02", "--hold", "5", "--force", "1"], ["02", "02", "--hold", "5", "extra"],
        ]
        for arguments in invalid {
            XCTAssertThrowsError(try Command.parse(["set"] + arguments).get(), "\(arguments)")
        }
    }

    func testRequiresRoot() throws {
        XCTAssertTrue(Command.set(try plan("02", "-", "--hold", "1")).requiresRoot)
    }

    func testWriteOrder() {
        func writes(_ plan: SetPlan) -> [String] {
            plan.writes.map { "\($0.key)=\(hex([$0.value.rawValue]))" }
        }
        XCTAssertEqual(writes(SetPlan(b: .block, c: .block, order: .bc, holdSeconds: 1)), ["CH0B=02", "CH0C=02"])
        XCTAssertEqual(writes(SetPlan(b: .block, c: .allow, order: .cb, holdSeconds: 1)), ["CH0C=00", "CH0B=02"])
        XCTAssertEqual(writes(SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 1)), ["CH0B=02"])
        XCTAssertEqual(writes(SetPlan(b: .block, c: nil, order: .cb, holdSeconds: 1)), ["CH0B=02"])
    }
}

final class SetExperimentTests: XCTestCase {
    private var lines: [String] = []
    private var ticks: [Int] = []

    private func run(
        _ smc: SMCAccess,
        _ plan: SetPlan,
        tick: ((Int) -> WaitOutcome)? = nil
    ) -> Int32 {
        lines = []
        ticks = []
        return SetExperiment.run(
            smc: smc,
            plan: plan,
            now: { Date(timeIntervalSince1970: 0) },
            tick: { [unowned self] milliseconds in
                self.ticks.append(milliseconds)
                return tick?(self.ticks.count) ?? .timeout
            },
            log: { [unowned self] in self.lines.append($0) }
        )
    }

    /// 줄에서 시각을 뺀 나머지: 쓰기 줄은 그대로, 값 줄은 `CH0B=02  CH0C=02`.
    private var events: [String] {
        lines.map { line in
            guard let range = line.range(of: "  CH0B=") else { return line }
            return String(line[line.index(range.lowerBound, offsetBy: 2)...])
        }
    }

    func testWritesHoldsThenRestoresPair() {
        let smc = SharedRegisterSMC()
        let code = run(smc, SetPlan(b: .block, c: .block, order: .bc, holdSeconds: 1))

        XCTAssertEqual(code, 0)
        XCTAssertEqual(smc.register, 0x00)
        XCTAssertEqual(smc.writes.map { "\($0.key)=\(hex($0.bytes))" }, ["CH0B=02", "CH0C=02", "CH0B=00", "CH0C=00"])

        // 실측 동작 모델: B←02 뒤 02/02, C←02 뒤 03/03, 유지 5번, 복구 중 B←00 뒤 01/01, C←00 뒤 00/00.
        XCTAssertEqual(Array(events.drop { $0.hasPrefix("현재") }), [
            "CH0B=00  CH0C=00",
            "쓰기 CH0B ← 02", "CH0B=02  CH0C=02",
            "쓰기 CH0C ← 02", "CH0B=03  CH0C=03",
            "1초 유지 (SIGINT/SIGTERM/SIGHUP을 받으면 바로 복구)",
            "CH0B=03  CH0C=03", "CH0B=03  CH0C=03", "CH0B=03  CH0C=03", "CH0B=03  CH0C=03", "CH0B=03  CH0C=03",
            "복구: 두 키에 00을 씀",
            "쓰기 CH0B ← 00", "CH0B=01  CH0C=01",
            "쓰기 CH0C ← 00", "CH0B=00  CH0C=00",
            "CH0B=00  CH0C=00",
            "복구 완료: 두 키 모두 00",
        ])
        XCTAssertEqual(ticks, Array(repeating: 200, count: 5))
    }

    func testDashSkipsCH0CButRestoreWritesBoth() {
        let smc = SharedRegisterSMC()
        let code = run(smc, SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 1))

        XCTAssertEqual(code, 0)
        XCTAssertEqual(smc.writes.map { "\($0.key)=\(hex($0.bytes))" }, ["CH0B=02", "CH0B=00", "CH0C=00"])
        XCTAssertTrue(events.contains("CH0B=02  CH0C=02"))
        XCTAssertFalse(events.contains("CH0B=03  CH0C=03"))
    }

    func testOrderCBWritesCH0CFirst() {
        let smc = SharedRegisterSMC()
        _ = run(smc, SetPlan(b: .block, c: .block, order: .cb, holdSeconds: 1))

        XCTAssertEqual(Array(smc.writes.prefix(2)).map { "\($0.key)" }, ["CH0C", "CH0B"])
        XCTAssertEqual(smc.register, 0x00)
    }

    func testSignalDuringHoldRestoresAndExitsWithSignalCode() {
        let smc = SharedRegisterSMC()
        let code = run(smc, SetPlan(b: .block, c: .block, order: .bc, holdSeconds: 120)) { count in
            count == 3 ? .signal(SIGINT) : .timeout
        }

        XCTAssertEqual(code, 130)
        XCTAssertEqual(smc.register, 0x00)
        XCTAssertEqual(ticks.count, 3)
        XCTAssertTrue(lines.contains("시그널 2을 받아 복구를 시작함"))
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
    }

    /// 복구 중 시그널이 계속 들어와도 복구는 끝까지 한다.
    func testSignalsDuringRestoreDoNotInterruptIt() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.transientReadsAfterWrite = [ch0c: [[0x01], [0x01], [0x01]]]
        let code = run(smc, SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 120)) { _ in .signal(SIGTERM) }

        XCTAssertEqual(code, 143)
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
    }

    func testWriteErrorRestoresAndExitsOne() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.failingWrites = [ch0c]
        smc.failingValue = 0x02
        let code = run(smc, SetPlan(b: .block, c: .block, order: .bc, holdSeconds: 10))

        XCTAssertEqual(code, 1)
        XCTAssertTrue(ticks.isEmpty)
        XCTAssertEqual(smc.value("CH0B"), [0x00])
        XCTAssertEqual(smc.value("CH0C"), [0x00])
        XCTAssertTrue(lines.contains("복구 완료: 두 키 모두 00"))
    }

    func testPreflightFailureWritesNothing() {
        let missing = FakeSMC(["CH0B": [0x00]])
        XCTAssertEqual(run(missing, SetPlan(b: .block, c: .block, order: .bc, holdSeconds: 1)), 1)
        XCTAssertTrue(missing.writes.isEmpty)

        let wrongSize = FakeSMC(["CH0B": [0x00], "CH0C": [0x00, 0x00]])
        XCTAssertEqual(run(wrongSize, SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 1)), 1)
        XCTAssertTrue(wrongSize.writes.isEmpty)
    }

    /// 복구 쓰기 중 하나가 오류를 내면, 값이 00/00으로 끝나더라도 실패로 종료한다.
    func testRestoreWriteErrorExitsOneEvenIfPairIsZero() {
        let smc = SharedRegisterSMC()
        smc.failingWrites = [ch0c]
        let code = run(smc, SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 1))

        XCTAssertEqual(code, 1)
        XCTAssertEqual(smc.register, 0x00)
        XCTAssertTrue(lines.contains { $0.hasPrefix("오류:") })
    }

    /// 5초(200ms × 25번) 동안 00/00이 되지 않으면 복구 실패로 끝난다.
    func testRestoreTimeoutExitsOne() {
        let smc = FakeSMC(["CH0B": [0x00], "CH0C": [0x00]])
        smc.settledValueAfterWrite = [ch0b: [0x01]]
        let code = run(smc, SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 1))

        XCTAssertEqual(code, 1)
        XCTAssertTrue(lines.contains { $0.hasPrefix("복구 실패") })
        XCTAssertFalse(lines.contains("복구 완료: 두 키 모두 00"))
        XCTAssertEqual(ticks.count, 5 + 25)
    }

    func testUnknownStartValueWarnsButProceeds() {
        let smc = SharedRegisterSMC(register: 0x01)
        let code = run(smc, SetPlan(b: .block, c: nil, order: .bc, holdSeconds: 1))

        XCTAssertEqual(code, 0)
        XCTAssertEqual(lines.filter { $0.hasPrefix("경고:") }.count, 2)
        XCTAssertEqual(smc.register, 0x00)
    }
}

final class SignalWaiterMillisecondTests: XCTestCase {
    func testSignalIsReportedOnEveryLaterWait() {
        let waiter = SignalWaiter()
        XCTAssertEqual(waiter.wait(milliseconds: 50), .timeout)
        kill(getpid(), SIGHUP)
        XCTAssertEqual(waiter.wait(milliseconds: 2_000), .signal(SIGHUP))
        XCTAssertEqual(waiter.wait(milliseconds: 2_000), .signal(SIGHUP))
    }
}
