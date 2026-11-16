import Foundation

/// 충전 제어에 필요한 SMC 접근. 테스트에서는 가짜 구현으로 바꾼다.
protocol SMCAccess {
    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo
    func read(_ key: FourCC) throws -> SMCValue
    func write(_ key: FourCC, bytes: [UInt8]) throws
}

/// 검증 중 읽힌 값이 바뀐 시점 하나.
struct Observation: Equatable {
    let bytes: [UInt8]
    let milliseconds: Int
}

enum ChargingError: Error, Equatable, CustomStringConvertible {
    case unexpectedDataSize(key: FourCC, size: Int)
    /// `observed`는 제한 시간 동안 읽힌 값의 변화 순서.
    case verifyFailed(key: FourCC, expected: UInt8, observed: [[UInt8]])

    var description: String {
        switch self {
        case .unexpectedDataSize(let key, let size):
            return "키 \(key): 크기가 \(size)바이트임 (1바이트여야 함). 아무것도 쓰지 않음"
        case .verifyFailed(let key, let expected, let observed):
            let sequence = observed.map(hex).joined(separator: " → ")
            return "키 \(key): 검증 실패 (기대 \(hex([expected])), 읽힌 값 \(sequence))"
        }
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { $0 < 0x10 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined(separator: " ")
}

/// 화이트리스트 키에 허용/차단 값을 쓰고 다시 읽어 검증한다.
struct ChargingController {
    /// 쓰기 직후 값이 잠시 다르게 읽힐 수 있어, 이 간격으로 제한 시간까지 다시 읽는다.
    static let verifyIntervalMilliseconds = 100
    static let verifyTimeoutMilliseconds = 2_000

    let smc: SMCAccess
    let log: (String) -> Void
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

    /// 충전 허용(00)으로 복구한다. 한 키가 실패해도 나머지 키는 계속 시도하고, 마지막에 첫 오류를 던진다.
    func enableCharging() throws {
        try preflight()
        try writeAllBestEffort(.allow)
        try confirmAll(.allow)
        log("완료: 충전 허용(00)으로 설정함")
    }

    /// 충전 차단(02)을 쓴다. 첫 실패에서 멈추고 두 키를 00으로 되돌리기를 시도한 뒤 원래 오류를 던진다.
    func disableCharging() throws {
        try preflight()
        do {
            for key in ChargingWhitelist.keys {
                try writeAndVerify(key, .block)
            }
            try confirmAll(.block)
        } catch {
            log("오류: \(error)")
            log("차단 쓰기가 실패해 충전 허용(00)으로 복구를 시도함")
            do {
                try writeAllBestEffort(.allow)
                try confirmAll(.allow)
                log("복구 완료: 두 키 모두 00")
            } catch {
                log("복구 실패: enable-charging을 다시 실행해 확인할 것")
            }
            throw error
        }
        log("완료: 충전 차단(02)으로 설정함")
    }

    /// 두 키가 모두 있고 1바이트인지 확인하고 현재 값을 출력한다. 하나라도 어긋나면 쓰기 전에 던진다.
    func preflight() throws {
        for key in ChargingWhitelist.keys {
            let info = try smc.keyInfo(key)
            guard info.dataSize == ChargingWhitelist.dataSize else {
                throw ChargingError.unexpectedDataSize(key: key, size: info.dataSize)
            }
        }
        for key in ChargingWhitelist.keys {
            let value = try smc.read(key)
            let state = ChargingState(bytes: value.bytes)
            log("현재 \(key) = \(hex(value.bytes)) (\(state.label))")
            if state == .unknown {
                log("경고: \(key) 값 \(hex(value.bytes))은 허용(00)도 차단(02)도 아님. 의미를 알 수 없지만 계속 진행함")
            }
        }
    }

    func writeAllBestEffort(_ value: ChargingValue) throws {
        var firstError: Error?
        for key in ChargingWhitelist.keys {
            do {
                try writeAndVerify(key, value)
            } catch {
                log("오류: \(error)")
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    func writeAndVerify(_ key: FourCC, _ value: ChargingValue) throws {
        log("쓰기 \(key) ← \(hex([value.rawValue]))")
        try smc.write(key, bytes: [value.rawValue])
        try pollUntilMatches(key, value)
        log("쓰기 확인 \(key) = \(hex([value.rawValue]))")
    }

    /// 다른 키를 쓰면서 앞서 쓴 키의 값이 바뀌었을 수 있으므로, 모든 쓰기가 끝난 뒤 두 키를 다시 확인한다.
    func confirmAll(_ value: ChargingValue) throws {
        for key in ChargingWhitelist.keys {
            try pollUntilMatches(key, value)
        }
        log("최종 확인: 두 키 모두 \(hex([value.rawValue]))")
    }

    /// 값이 기대값과 같아질 때까지 일정 간격으로 읽는다. 읽힌 값의 변화 순서를 출력하고,
    /// 제한 시간까지 맞지 않으면 던진다.
    func pollUntilMatches(_ key: FourCC, _ value: ChargingValue) throws {
        let expected = [value.rawValue]
        let interval = Self.verifyIntervalMilliseconds
        var changes: [Observation] = []
        var matched = false

        var elapsed = 0
        while true {
            let bytes = try smc.read(key).bytes
            if changes.last?.bytes != bytes {
                changes.append(Observation(bytes: bytes, milliseconds: elapsed))
            }
            if bytes == expected {
                matched = true
                break
            }
            guard elapsed + interval <= Self.verifyTimeoutMilliseconds else { break }
            sleep(Double(interval) / 1000)
            elapsed += interval
        }

        let sequence = changes.map { "\(hex($0.bytes)) (\($0.milliseconds)ms)" }.joined(separator: " → ")
        log("읽기 변화 \(key): \(sequence)")
        guard matched else {
            log("\(key): \(Self.verifyTimeoutMilliseconds)ms 동안 \(hex(expected))이 되지 않음")
            throw ChargingError.verifyFailed(key: key, expected: value.rawValue, observed: changes.map(\.bytes))
        }
    }
}
