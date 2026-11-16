/// 쓰기를 허용하는 값. 이 두 값 외에는 어떤 값도 쓰지 않는다.
enum ChargingValue: UInt8, CaseIterable {
    case allow = 0x00
    case block = 0x02
}

/// `CH0B/CH0C` 쌍으로 읽힌 값의 해석. 키 값만 설명하며, 실제 충전 상태를 뜻하지 않는다.
///
/// 실측에 따른 가설: 두 키는 읽을 때 항상 같은 값으로 보이고,
/// CH0B에 02를 쓰면 0x02 자리가, CH0C에 02를 쓰면 0x01 자리가 켜진다.
enum PairState: Equatable {
    /// 00/00
    case clear
    /// 02/02
    case blockedByCH0B
    /// 01/01
    case blockedByCH0C
    /// 03/03
    case blockedByBoth
    /// 그 외(두 키의 값이 다르거나, 알려지지 않은 값).
    case unrecognized

    init(b: [UInt8], c: [UInt8]) {
        guard b == c, b.count == 1 else {
            self = .unrecognized
            return
        }
        switch b[0] {
        case 0x00: self = .clear
        case 0x02: self = .blockedByCH0B
        case 0x01: self = .blockedByCH0C
        case 0x03: self = .blockedByBoth
        default: self = .unrecognized
        }
    }

    var label: String {
        switch self {
        case .clear: return "차단 값 없음"
        case .blockedByCH0B: return "CH0B 차단 값만 설정됨"
        case .blockedByCH0C: return "CH0C 차단 값만 설정됨"
        case .blockedByBoth: return "CH0B, CH0C 차단 값 모두 설정됨"
        case .unrecognized: return "알려지지 않은 조합"
        }
    }
}

/// 쓰기 화이트리스트: 키 2개(CH0B, CH0C) × 값 2개(00, 02), 각 1바이트.
enum ChargingWhitelist {
    /// 쓰는 순서대로 나열한다.
    static let keys: [FourCC] = [FourCC("CH0B")!, FourCC("CH0C")!]
    /// disable-charging이 02를 쓰는 유일한 키.
    static let blockKey = keys[0]
    static let dataSize = 1

    static func permits(key: FourCC, bytes: [UInt8]) -> Bool {
        guard keys.contains(key), bytes.count == dataSize else { return false }
        return ChargingValue(rawValue: bytes[0]) != nil
    }
}
