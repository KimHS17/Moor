import XCTest
@testable import MoorCore

final class ChargePolicyTests: XCTestCase {
    private func decide(_ percent: Int, upper: Int, lower: Int, charging: Bool) -> ChargeDecision {
        ChargePolicy.decide(percent: percent, upperLimit: upper, lowerLimit: lower, isCharging: charging)
    }

    func testDefaultLimitIs55() {
        XCTAssertEqual(ChargePolicy.defaultLimit, 55)
    }

    // MARK: 55% 단순 한도 (하한 == 상한)

    func testSimpleLimit() {
        let limit = ChargePolicy.defaultLimit
        for charging in [true, false] {
            XCTAssertEqual(decide(54, upper: limit, lower: limit, charging: charging), .allow)
            XCTAssertEqual(decide(55, upper: limit, lower: limit, charging: charging), .block)
            XCTAssertEqual(decide(56, upper: limit, lower: limit, charging: charging), .block)
        }
    }

    // MARK: 항해 모드 (50~55)

    func testSailingBlocksAtOrAboveUpper() {
        for charging in [true, false] {
            XCTAssertEqual(decide(55, upper: 55, lower: 50, charging: charging), .block)
            XCTAssertEqual(decide(80, upper: 55, lower: 50, charging: charging), .block)
        }
    }

    func testSailingAllowsAtOrBelowLower() {
        for charging in [true, false] {
            XCTAssertEqual(decide(50, upper: 55, lower: 50, charging: charging), .allow)
            XCTAssertEqual(decide(30, upper: 55, lower: 50, charging: charging), .allow)
        }
    }

    func testSailingDoesNotResumeInsideBand() {
        XCTAssertEqual(decide(51, upper: 55, lower: 50, charging: false), .block)
        XCTAssertEqual(decide(54, upper: 55, lower: 50, charging: false), .block)
    }

    func testSailingKeepsChargingInsideBand() {
        XCTAssertEqual(decide(51, upper: 55, lower: 50, charging: true), .allow)
        XCTAssertEqual(decide(54, upper: 55, lower: 50, charging: true), .allow)
    }

    /// 방전 → 하한에서 재개 → 상한에서 다시 차단되는 전체 흐름.
    /// 직전 판정이 다음 시점의 충전 중 여부가 된다고 가정한다.
    func testSailingScenario() {
        let steps: [(percent: Int, expected: ChargeDecision)] = [
            (56, .block), (53, .block), (51, .block),
            (50, .allow), (53, .allow), (55, .block), (54, .block),
        ]
        var charging = false
        for step in steps {
            let decision = decide(step.percent, upper: 55, lower: 50, charging: charging)
            XCTAssertEqual(decision, step.expected, "percent=\(step.percent)")
            charging = decision == .allow
        }
    }

    // MARK: fail-safe

    func testInvalidInputAllowsCharging() {
        XCTAssertEqual(decide(90, upper: 50, lower: 55, charging: false), .allow) // 하한 > 상한
        XCTAssertEqual(decide(90, upper: 101, lower: 50, charging: false), .allow)
        XCTAssertEqual(decide(90, upper: 55, lower: -1, charging: false), .allow)
        XCTAssertEqual(decide(-1, upper: 55, lower: 50, charging: false), .allow)
        XCTAssertEqual(decide(101, upper: 55, lower: 50, charging: false), .allow)
    }
}
