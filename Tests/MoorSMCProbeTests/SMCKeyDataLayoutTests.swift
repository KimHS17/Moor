import XCTest
@testable import MoorSMCProbe

/// 커널 인터페이스와 구조체 레이아웃이 일치하는지 검증한다.
final class SMCKeyDataLayoutTests: XCTestCase {
    func testTotalSizeIs80Bytes() {
        XCTAssertEqual(MemoryLayout<SMCKeyData>.size, 80)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.stride, 80)
    }

    func testFieldOffsets() {
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.key), 0)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.versMajor), 4)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.versRelease), 8)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.pLimitVersion), 12)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.pLimitLength), 14)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.cpuPLimit), 16)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.gpuPLimit), 20)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.memPLimit), 24)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.dataSize), 28)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.dataType), 32)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.dataAttributes), 36)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.result), 40)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.status), 41)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.command), 42)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.data32), 44)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.offset(of: \.bytes), 48)
    }

    func testDataRegionIs32Bytes() {
        XCTAssertEqual(MemoryLayout<SMCKeyData.Bytes>.size, SMCKeyData.maxDataSize)
    }

    func testDataBytesReadsPrefixAndClampsCount() {
        var data = SMCKeyData()
        data.bytes.0 = 0x02
        data.bytes.1 = 0xAB
        XCTAssertEqual(data.dataBytes(count: 1), [0x02])
        XCTAssertEqual(data.dataBytes(count: 2), [0x02, 0xAB])
        XCTAssertEqual(data.dataBytes(count: 99).count, 32)
        XCTAssertEqual(data.dataBytes(count: -1), [])
    }

    func testSetDataBytesWritesAtOffset48() {
        var data = SMCKeyData()
        data.setDataBytes([0x02])
        XCTAssertEqual(data.dataBytes(count: 2), [0x02, 0x00])
        withUnsafeBytes(of: data) { XCTAssertEqual($0[48], 0x02) }
    }
}
