import Foundation

/// 충전 제어에 필요한 SMC 접근. 테스트에서는 가짜 구현으로 바꾼다.
protocol SMCAccess {
    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo
    func read(_ key: FourCC) throws -> SMCValue
    func write(_ key: FourCC, bytes: [UInt8]) throws
}

enum ChargingError: Error, Equatable, CustomStringConvertible {
    case unexpectedDataSize(key: FourCC, size: Int)
    /// `observed`는 `CH0B/CH0C` 쌍이 읽힌 변화 순서(예: `["03/03", "01/01"]`).
    case pairVerifyFailed(expected: UInt8, observed: [String])

    var description: String {
        switch self {
        case .unexpectedDataSize(let key, let size):
            return "키 \(key): 크기가 \(size)바이트임 (1바이트여야 함). 아무것도 쓰지 않음"
        case .pairVerifyFailed(let expected, let observed):
            let want = hex([expected])
            return "쌍 검증 실패 (기대 \(want)/\(want), 읽힌 값 \(observed.joined(separator: " → ")))"
        }
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { $0 < 0x10 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined(separator: " ")
}

/// 화이트리스트 키에 값을 쓰고 `CH0B/CH0C` 쌍을 다시 읽어 검증한다.
///
/// 검증은 키 값만 본다. 실제로 충전이 멈췄는지, 재개됐는지는 판단하지 않는다
/// (실측에서 충전 상태는 키 값이 바뀐 뒤 수십 초 지나서 따라왔다).
struct ChargingController {
    static let verifyIntervalMilliseconds = 100
    static let verifyTimeoutMilliseconds = 2_000
    static let chargingNote = "실제 충전 상태는 확인하지 않음. 반영에 수십 초 걸릴 수 있음"

    private static let pairName = ChargingWhitelist.keys.map(\.description).joined(separator: "/")

    let smc: SMCAccess
    let log: (String) -> Void
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

    /// CH0B와 CH0C에 모두 00을 쓰고 쌍이 00/00이 될 때까지 본다.
    func enableCharging() throws {
        try preflight()
        try writeBothAllowAndConfirm()
        log("완료: 키 값이 00/00이 됨. \(Self.chargingNote)")
    }

    /// CH0B에만 02를 쓰고 쌍이 02/02가 될 때까지 본다. 실패하면 두 키를 00으로 되돌리기를 시도한 뒤
    /// 원래 오류를 던진다.
    func disableCharging() throws {
        try preflight()
        do {
            try write(ChargingWhitelist.blockKey, .block)
            try confirmPair(.block)
        } catch {
            log("오류: \(error)")
            log("차단 쓰기가 실패해 두 키를 00으로 되돌리기를 시도함")
            do {
                try writeBothAllowAndConfirm()
                log("복구 완료: 두 키 모두 00")
            } catch {
                log("복구 실패: enable-charging을 다시 실행해 확인할 것")
            }
            throw error
        }
        log("완료: 키 값이 02/02가 됨. \(Self.chargingNote)")
    }

    /// 두 키에 모두 00을 쓴 뒤 쌍이 00/00이 되는지 본다. 키 하나를 쓴 직후의 값은 검증하지 않는다.
    /// 한 키의 쓰기가 실패해도 나머지 키는 쓰고, 쓰기 오류가 있었으면 그 오류를 던진다.
    func writeBothAllowAndConfirm() throws {
        var firstError: Error?
        for key in ChargingWhitelist.keys {
            do {
                try write(key, .allow)
            } catch {
                log("오류: \(error)")
                if firstError == nil { firstError = error }
            }
        }
        do {
            try confirmPair(.allow)
        } catch {
            throw firstError ?? error
        }
        if let firstError { throw firstError }
    }

    /// 두 키가 모두 있고 1바이트인지 확인하고 현재 쌍을 해석해 출력한다.
    /// 키가 없거나 크기가 다르면 쓰기 전에 던진다. 알려지지 않은 조합은 경고만 하고 진행한다.
    func preflight() throws {
        for key in ChargingWhitelist.keys {
            let info = try smc.keyInfo(key)
            guard info.dataSize == ChargingWhitelist.dataSize else {
                throw ChargingError.unexpectedDataSize(key: key, size: info.dataSize)
            }
        }
        let pair = try readPair()
        log("현재 \(Self.pairName) = \(pair.text) (\(pair.state.label))")
        warnIfUnrecognized(pair)
    }

    private func write(_ key: FourCC, _ value: ChargingValue) throws {
        log("쓰기 \(key) ← \(hex([value.rawValue]))")
        try smc.write(key, bytes: [value.rawValue])
    }

    private func readPair() throws -> (text: String, state: PairState) {
        let values = try ChargingWhitelist.keys.map { try smc.read($0).bytes }
        return (values.map(hex).joined(separator: "/"), PairState(b: values[0], c: values[1]))
    }

    private func warnIfUnrecognized(_ pair: (text: String, state: PairState)) {
        if pair.state == .unrecognized {
            log("경고: \(pair.text)은 알려진 조합(00/00, 02/02, 01/01, 03/03)이 아님")
        }
    }

    /// 두 키를 함께 읽어 쌍이 모두 기대값이 될 때까지 일정 간격으로 본다.
    /// 쌍의 변화 순서와 마지막 쌍의 해석을 출력하고, 제한 시간까지 맞지 않으면 던진다.
    func confirmPair(_ value: ChargingValue) throws {
        let want = hex([value.rawValue])
        let expected = "\(want)/\(want)"
        let interval = Self.verifyIntervalMilliseconds
        var changes: [(text: String, milliseconds: Int)] = []
        var last = try readPair()
        changes.append((last.text, 0))

        var elapsed = 0
        while last.text != expected, elapsed + interval <= Self.verifyTimeoutMilliseconds {
            sleep(Double(interval) / 1000)
            elapsed += interval
            last = try readPair()
            if changes.last?.text != last.text { changes.append((last.text, elapsed)) }
        }

        log("읽기 변화 \(Self.pairName): " + changes.map { "\($0.text) (\($0.milliseconds)ms)" }.joined(separator: " → "))
        log("최종 \(Self.pairName) = \(last.text) (\(last.state.label))")
        guard last.text == expected else {
            warnIfUnrecognized(last)
            throw ChargingError.pairVerifyFailed(expected: value.rawValue, observed: changes.map(\.text))
        }
    }
}
