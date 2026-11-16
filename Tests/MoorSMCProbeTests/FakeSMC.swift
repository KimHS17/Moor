@testable import MoorSMCProbe

struct FakeSMCFailure: Error, Equatable {}

/// 메모리 안에서만 동작하는 가짜 SMC. 실제 `SMCConnection`처럼 화이트리스트 밖 쓰기는 거부한다.
final class FakeSMC: SMCAccess {
    var values: [FourCC: [UInt8]]
    /// 쓰기 호출이 오류를 던지는 키.
    var failingWrites: Set<FourCC> = []
    /// 쓰기는 성공하지만 값이 바뀌지 않는 키(검증 실패 재현용).
    var ignoredWrites: Set<FourCC> = []
    /// 지정한 값을 쓸 때만 실패하게 한다. nil이면 모든 값에 적용.
    var failingValue: UInt8?
    private(set) var writes: [(key: FourCC, bytes: [UInt8])] = []

    init(_ values: [String: [UInt8]]) {
        self.values = Dictionary(uniqueKeysWithValues: values.map { (FourCC($0.key)!, $0.value) })
    }

    func value(_ key: String) -> [UInt8]? { values[FourCC(key)!] }

    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo {
        guard let bytes = values[key] else { throw SMCError.keyNotFound(key) }
        return SMCKeyInfo(dataSize: bytes.count, dataType: FourCC("hex_")!)
    }

    func read(_ key: FourCC) throws -> SMCValue {
        let info = try keyInfo(key)
        return SMCValue(key: key, info: info, bytes: values[key]!)
    }

    func write(_ key: FourCC, bytes: [UInt8]) throws {
        guard ChargingWhitelist.permits(key: key, bytes: bytes) else {
            throw SMCError.notWhitelisted(key: key, bytes: bytes)
        }
        writes.append((key, bytes))
        let applies = failingValue == nil || failingValue == bytes.first
        if applies && failingWrites.contains(key) { throw FakeSMCFailure() }
        if applies && ignoredWrites.contains(key) { return }
        values[key] = bytes
    }
}
