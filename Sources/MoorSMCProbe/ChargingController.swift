/// 충전 제어에 필요한 SMC 접근. 테스트에서는 가짜 구현으로 바꾼다.
protocol SMCAccess {
    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo
    func read(_ key: FourCC) throws -> SMCValue
    func write(_ key: FourCC, bytes: [UInt8]) throws
}

enum ChargingError: Error, Equatable, CustomStringConvertible {
    case unexpectedDataSize(key: FourCC, size: Int)
    case verifyFailed(key: FourCC, expected: UInt8, actual: [UInt8])

    var description: String {
        switch self {
        case .unexpectedDataSize(let key, let size):
            return "키 \(key): 크기가 \(size)바이트임 (1바이트여야 함). 아무것도 쓰지 않음"
        case .verifyFailed(let key, let expected, let actual):
            return "키 \(key): 쓰기 후 검증 실패 (기대 \(hex([expected])), 실제 \(hex(actual)))"
        }
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { $0 < 0x10 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined(separator: " ")
}

/// 화이트리스트 키에 허용/차단 값을 쓰고 다시 읽어 검증한다.
struct ChargingController {
    let smc: SMCAccess
    let log: (String) -> Void

    /// 충전 허용(00)으로 복구한다. 한 키가 실패해도 나머지 키는 계속 시도하고, 마지막에 첫 오류를 던진다.
    func enableCharging() throws {
        try preflight()
        try writeAllBestEffort(.allow)
        log("완료: 충전 허용(00)으로 설정함")
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
        try smc.write(key, bytes: [value.rawValue])
        let actual = try smc.read(key).bytes
        guard actual == [value.rawValue] else {
            throw ChargingError.verifyFailed(key: key, expected: value.rawValue, actual: actual)
        }
        log("쓰기 확인 \(key) = \(hex(actual))")
    }
}
