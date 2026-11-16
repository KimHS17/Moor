import Foundation
import IOKit

enum SMCError: Error, Equatable, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyNotFound(FourCC)
    case smcResult(key: FourCC, code: UInt8)
    case unsupportedDataSize(key: FourCC, size: Int)
    case notWhitelisted(key: FourCC, bytes: [UInt8])

    var description: String {
        switch self {
        case .serviceNotFound:
            return "AppleSMC 서비스를 찾을 수 없음"
        case .openFailed(let code):
            return "AppleSMC 열기 실패 (kern_return 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case .callFailed(let code):
            return "SMC 호출 실패 (kern_return 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case .keyNotFound(let key):
            return "키 \(key) 없음"
        case .smcResult(let key, let code):
            return "키 \(key): SMC 결과 코드 0x\(String(code, radix: 16))"
        case .unsupportedDataSize(let key, let size):
            return "키 \(key): 지원하지 않는 데이터 크기 \(size)"
        case .notWhitelisted(let key, let bytes):
            return "키 \(key)에 값 \(hex(bytes)) 쓰기는 화이트리스트에 없어 거부함"
        }
    }
}

/// AppleSMC 사용자 클라이언트 연결. 쓰기는 `ChargingWhitelist`가 허용하는 키와 값만 받는다.
final class SMCConnection: SMCAccess {
    private static let structMethodSelector: UInt32 = 2
    private static let commandReadBytes: UInt8 = 5
    private static let commandWriteBytes: UInt8 = 6
    private static let commandReadKeyInfo: UInt8 = 9
    private static let resultKeyNotFound: UInt8 = 0x84

    private var connection: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        let status = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard status == kIOReturnSuccess else { throw SMCError.openFailed(status) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func keyInfo(_ key: FourCC) throws -> SMCKeyInfo {
        var input = SMCKeyData()
        input.key = key.rawValue
        input.command = Self.commandReadKeyInfo

        let output = try call(input, key: key)
        let size = Int(output.dataSize)
        // 일부 펌웨어는 크기 0인 자리표시 키 정보를 돌려준다. 읽을 수 없으므로 없는 키로 본다.
        guard size > 0 else { throw SMCError.keyNotFound(key) }
        guard size <= SMCKeyData.maxDataSize else { throw SMCError.unsupportedDataSize(key: key, size: size) }
        return SMCKeyInfo(dataSize: size, dataType: FourCC(rawValue: output.dataType))
    }

    func read(_ key: FourCC) throws -> SMCValue {
        let info = try keyInfo(key)

        var input = SMCKeyData()
        input.key = key.rawValue
        input.dataSize = UInt32(info.dataSize)
        input.command = Self.commandReadBytes

        let output = try call(input, key: key)
        return SMCValue(key: key, info: info, bytes: output.dataBytes(count: info.dataSize))
    }

    /// 화이트리스트에 없는 키나 값이면 SMC를 호출하지 않고 던진다. root 권한이 필요하다.
    func write(_ key: FourCC, bytes: [UInt8]) throws {
        guard ChargingWhitelist.permits(key: key, bytes: bytes) else {
            throw SMCError.notWhitelisted(key: key, bytes: bytes)
        }

        var input = SMCKeyData()
        input.key = key.rawValue
        input.dataSize = UInt32(bytes.count)
        input.command = Self.commandWriteBytes
        input.setDataBytes(bytes)

        _ = try call(input, key: key)
    }

    private func call(_ input: SMCKeyData, key: FourCC) throws -> SMCKeyData {
        var input = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        let status = IOConnectCallStructMethod(
            connection, Self.structMethodSelector,
            &input, MemoryLayout<SMCKeyData>.size,
            &output, &outputSize
        )
        guard status == kIOReturnSuccess else { throw SMCError.callFailed(status) }
        guard output.result != Self.resultKeyNotFound else { throw SMCError.keyNotFound(key) }
        guard output.result == 0 else { throw SMCError.smcResult(key: key, code: output.result) }
        return output
    }
}
