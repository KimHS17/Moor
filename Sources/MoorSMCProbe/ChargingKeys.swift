/// 쓰기를 허용하는 값. 이 두 값 외에는 어떤 값도 쓰지 않는다.
enum ChargingValue: UInt8, CaseIterable {
    case allow = 0x00
    case block = 0x02
}

/// 키 하나의 현재 값을 해석한 결과.
enum ChargingState: Equatable {
    case allowed
    case blocked
    /// 00도 02도 아닌 값(예: 01). 의미를 확인하지 못한 상태.
    case unknown

    init(bytes: [UInt8]) {
        switch bytes {
        case [ChargingValue.allow.rawValue]: self = .allowed
        case [ChargingValue.block.rawValue]: self = .blocked
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .allowed: return "충전 허용"
        case .blocked: return "충전 차단"
        case .unknown: return "알 수 없음"
        }
    }
}

/// 쓰기 화이트리스트: 키 2개(CH0B, CH0C) × 값 2개(00, 02), 각 1바이트.
enum ChargingWhitelist {
    /// 쓰는 순서대로 나열한다.
    static let keys: [FourCC] = [FourCC("CH0B")!, FourCC("CH0C")!]
    static let dataSize = 1

    static func permits(key: FourCC, bytes: [UInt8]) -> Bool {
        guard keys.contains(key), bytes.count == dataSize else { return false }
        return ChargingValue(rawValue: bytes[0]) != nil
    }
}
