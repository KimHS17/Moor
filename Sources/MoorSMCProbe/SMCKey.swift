/// SMC 키와 데이터 타입에 쓰이는 4글자 코드. 첫 글자가 최상위 바이트다.
struct FourCC: Hashable, CustomStringConvertible {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// 정확히 4바이트의 출력 가능한 ASCII 문자열만 받는다.
    init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        self.rawValue = bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    var description: String {
        let bytes = (0..<4).map { UInt8(truncatingIfNeeded: rawValue >> (24 - 8 * UInt32($0))) }
        return String(bytes.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "?" })
    }
}

struct SMCKeyInfo: Equatable {
    let dataSize: Int
    let dataType: FourCC
}

struct SMCValue: Equatable {
    let key: FourCC
    let info: SMCKeyInfo
    let bytes: [UInt8]

    var hexString: String {
        hex(bytes)
    }

    /// 예: `CH0B  [ui8 ]  1 byte(s)  00`
    var formatted: String {
        "\(key)  [\(info.dataType)]  \(info.dataSize) byte(s)  \(hexString)"
    }
}
