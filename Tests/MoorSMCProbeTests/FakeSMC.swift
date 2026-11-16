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
    /// 키에 쓴 직후 읽기에서 차례로 돌려줄 일시적인 값. 다 쓰면 실제 값으로 돌아간다.
    var transientReadsAfterWrite: [FourCC: [[UInt8]]] = [:]
    /// 쓴 값과 무관하게 최종적으로 자리 잡는 값(끝까지 맞지 않는 상황 재현용).
    var settledValueAfterWrite: [FourCC: [UInt8]] = [:]
    private var pendingReads: [FourCC: [[UInt8]]] = [:]
    private(set) var readCounts: [FourCC: Int] = [:]
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
        readCounts[key, default: 0] += 1
        if var pending = pendingReads[key], !pending.isEmpty {
            let bytes = pending.removeFirst()
            pendingReads[key] = pending
            return SMCValue(key: key, info: info, bytes: bytes)
        }
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
        values[key] = settledValueAfterWrite[key] ?? bytes
        pendingReads[key] = transientReadsAfterWrite[key]
    }
}
