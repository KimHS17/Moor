@testable import MoorSMCProbe

/// 2026-11-16 실측에서 본 동작을 흉내 낸 가짜 SMC.
///
/// 두 키가 항상 같은 값으로 읽힌다. CH0B에 02를 쓰면 02 자리가, CH0C에 02를 쓰면 01 자리가 켜지고,
/// 각 키에 00을 쓰면 그 키의 자리만 꺼진다. (B←02: 02, 이어서 C←02: 03, B←00: 01, C←00: 00)
/// 관찰과 일치하도록 만든 모델일 뿐, 실제 펌웨어 동작이라고 확인된 것은 아니다.
final class SharedRegisterSMC: SMCAccess {
    private static let b = FourCC("CH0B")!
    private static let c = FourCC("CH0C")!

    var register: UInt8
    var failingWrites: Set<FourCC> = []
    private(set) var writes: [(key: FourCC, bytes: [UInt8])] = []

    init(register: UInt8 = 0x00) { self.register = register }

    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo {
        guard key == Self.b || key == Self.c else { throw SMCError.keyNotFound(key) }
        return SMCKeyInfo(dataSize: 1, dataType: FourCC("hex_")!)
    }

    func read(_ key: FourCC) throws -> SMCValue {
        SMCValue(key: key, info: try keyInfo(key), bytes: [register])
    }

    func write(_ key: FourCC, bytes: [UInt8]) throws {
        guard ChargingWhitelist.permits(key: key, bytes: bytes) else {
            throw SMCError.notWhitelisted(key: key, bytes: bytes)
        }
        writes.append((key, bytes))
        if failingWrites.contains(key) { throw FakeSMCFailure() }
        let bit: UInt8 = key == Self.b ? 0x02 : 0x01
        if bytes[0] == 0x00 { register &= ~bit } else { register |= bit }
    }
}
