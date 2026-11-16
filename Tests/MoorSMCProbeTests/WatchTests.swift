import XCTest
@testable import MoorSMCProbe

private let ch0b = FourCC("CH0B")!
private let ch0c = FourCC("CH0C")!

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
