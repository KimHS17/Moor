/// AppleSMC 사용자 클라이언트에 넘기는 80바이트 입출력 구조체.
///
/// 커널 인터페이스와 필드 오프셋이 정확히 같아야 한다. Swift는 중첩 구조체의 꼬리 패딩에
/// 다음 필드를 채워 넣을 수 있어서, 중첩 없이 펼치고 패딩을 명시적으로 선언했다.
/// 오프셋은 `SMCKeyDataLayoutTests`가 검증한다.
struct SMCKeyData {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    static let maxDataSize = 32

    var key: UInt32 = 0                 // 0

    // 버전 정보 (이 도구에서는 쓰지 않음)
    var versMajor: UInt8 = 0            // 4
    var versMinor: UInt8 = 0            // 5
    var versBuild: UInt8 = 0            // 6
    var versReserved: UInt8 = 0         // 7
    var versRelease: UInt16 = 0         // 8
    var padding0: UInt16 = 0            // 10

    // 전력 한도 정보 (이 도구에서는 쓰지 않음)
    var pLimitVersion: UInt16 = 0       // 12
    var pLimitLength: UInt16 = 0        // 14
    var cpuPLimit: UInt32 = 0           // 16
    var gpuPLimit: UInt32 = 0           // 20
    var memPLimit: UInt32 = 0           // 24

    // 키 정보
    var dataSize: UInt32 = 0            // 28
    var dataType: UInt32 = 0            // 32
    var dataAttributes: UInt8 = 0       // 36
    var padding1: UInt8 = 0             // 37
    var padding2: UInt8 = 0             // 38
    var padding3: UInt8 = 0             // 39

    var result: UInt8 = 0               // 40
    var status: UInt8 = 0               // 41
    var command: UInt8 = 0              // 42 (data8)
    var data32: UInt32 = 0              // 44
    var bytes: Bytes = (                // 48
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    /// `bytes` 앞쪽 `count`바이트를 배열로 꺼낸다.
    func dataBytes(count: Int) -> [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0.prefix(max(0, min(count, Self.maxDataSize)))) }
    }

    /// `bytes` 앞쪽에 값을 복사한다. 32바이트를 넘는 부분은 버린다.
    mutating func setDataBytes(_ source: [UInt8]) {
        withUnsafeMutableBytes(of: &bytes) { buffer in
            for (index, byte) in source.prefix(Self.maxDataSize).enumerated() {
                buffer[index] = byte
            }
        }
    }
}
