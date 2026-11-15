import XCTest
@testable import MoorSMCProbe

final class FourCCTests: XCTestCase {
    func testEncodesFirstCharacterAsHighByte() {
        XCTAssertEqual(FourCC("CH0B")?.rawValue, 0x4348_3042)
        XCTAssertEqual(FourCC("ui8 ")?.rawValue, 0x7569_3820)
    }

    func testRoundTripsToString() {
        XCTAssertEqual(FourCC("CH0C")?.description, "CH0C")
        XCTAssertEqual(FourCC(rawValue: 0x7569_3820).description, "ui8 ")
    }

    func testRejectsWrongLengthOrNonASCII() {
        XCTAssertNil(FourCC(""))
        XCTAssertNil(FourCC("CH0"))
        XCTAssertNil(FourCC("CH0BC"))
        XCTAssertNil(FourCC("CH0é"))
        XCTAssertNil(FourCC("CH\n0"))
    }

    func testUnprintableBytesAreMaskedInDescription() {
        XCTAssertEqual(FourCC(rawValue: 0x4300_0042).description, "C??B")
    }
}

final class CommandTests: XCTestCase {
    func testParsesReadWithMultipleKeys() {
        XCTAssertEqual(
            Command.parse(["read", "CH0B", "CH0C"]),
            .success(.read([FourCC("CH0B")!, FourCC("CH0C")!]))
        )
    }

    func testRejectsMissingSubcommand() {
        XCTAssertThrowsError(try Command.parse([]).get())
    }

    func testRejectsReadWithoutKeys() {
        XCTAssertThrowsError(try Command.parse(["read"]).get())
    }

    func testRejectsInvalidKey() {
        XCTAssertThrowsError(try Command.parse(["read", "CH0B", "TOOLONG"]).get())
    }

    /// 쓰기 서브커맨드는 아직 없다. 임의 키 쓰기는 앞으로도 만들지 않는다.
    func testRejectsUnknownAndWriteSubcommands() {
        for name in ["write", "enable-charging", "disable-charging", "bogus"] {
            XCTAssertThrowsError(try Command.parse([name, "CH0B"]).get(), name)
        }
    }
}

final class SMCValueTests: XCTestCase {
    func testFormatsHexWithLeadingZeros() {
        let value = SMCValue(
            key: FourCC("CH0B")!,
            info: SMCKeyInfo(dataSize: 2, dataType: FourCC("ui16")!),
            bytes: [0x00, 0xAB]
        )
        XCTAssertEqual(value.hexString, "00 ab")
        XCTAssertEqual(value.formatted, "CH0B  [ui16]  2 byte(s)  00 ab")
    }
}
