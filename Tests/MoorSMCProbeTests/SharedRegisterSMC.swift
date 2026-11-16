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
    /// 쓰기는 성공하지만 값이 바뀌지 않는 키.
    var ignoredWrites: Set<FourCC> = []
    /// 쓴 뒤 이 횟수만큼의 읽기는 쓰기 전 값을 돌려준다(값이 늦게 바뀌는 상황 재현용).
    var staleReadsAfterWrite = 0
    private var staleValue: UInt8 = 0
    private var staleRemaining = 0
    private(set) var readCount = 0
    private(set) var writes: [(key: FourCC, bytes: [UInt8])] = []

    init(register: UInt8 = 0x00) { self.register = register }

    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo {
        guard key == Self.b || key == Self.c else { throw SMCError.keyNotFound(key) }
        return SMCKeyInfo(dataSize: 1, dataType: FourCC("hex_")!)
    }

    func read(_ key: FourCC) throws -> SMCValue {
        let info = try keyInfo(key)
        readCount += 1
        if staleRemaining > 0 {
            staleRemaining -= 1
            return SMCValue(key: key, info: info, bytes: [staleValue])
        }
        return SMCValue(key: key, info: info, bytes: [register])
    }

    func write(_ key: FourCC, bytes: [UInt8]) throws {
        guard ChargingWhitelist.permits(key: key, bytes: bytes) else {
            throw SMCError.notWhitelisted(key: key, bytes: bytes)
        }
        writes.append((key, bytes))
        if failingWrites.contains(key) { throw FakeSMCFailure() }
        if ignoredWrites.contains(key) { return }
        // 연속으로 쓰면 첫 쓰기 전의 값이 계속 보이게 한다.
        if staleRemaining == 0 { staleValue = register }
        staleRemaining = staleReadsAfterWrite
        let bit: UInt8 = key == Self.b ? 0x02 : 0x01
        if bytes[0] == 0x00 { register &= ~bit } else { register |= bit }
    }
}
