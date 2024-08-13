@testable import MoqLoc
import XCTest

final class Test: XCTestCase {
    func testRoundtrip() throws {
        try roundtrip(multiplier: 1)
    }

    func testLargerBuffer() throws {
        try roundtrip(multiplier: 2)
    }

    func testBufferTooSmall() throws {
        XCTAssertThrowsError(try roundtrip(multiplier: 0.5)) { error in
            switch error {
            case LowOverheadContainerError.bufferTooSmall(let size):
                XCTAssertEqual(size, 21)
            default:
                XCTFail(error.localizedDescription)
            }
        }
    }

    func roundtrip(multiplier: Double) throws {
        let now = Date.now
        let header = LowOverheadContainer.Header(timestamp: now,
                                                 sequenceNumber: 101)
        let payload = Data([1, 2, 3, 4])
        let loc = LowOverheadContainer(header: header,
                                       payload: [payload])

        // Encode.
        var buffer = Data(count: Int(Double(loc.getRequiredBytes()) * multiplier))
        _ = try buffer.withUnsafeMutableBytes {
            try loc.serialize(into: $0)
        }

        // Decode.
        try buffer.withUnsafeBytes {
            let decoded = try LowOverheadContainer(encoded: $0, noCopy: true)
            XCTAssertEqual(loc.header.timestamp, decoded.header.timestamp)
            XCTAssertEqual(loc.header.sequenceNumber, decoded.header.sequenceNumber)
            XCTAssertEqual(loc.payload, decoded.payload)
        }
    }
}
