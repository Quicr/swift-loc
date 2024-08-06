@testable import MoqLoc
import XCTest

final class Test: XCTestCase {
    func testRoundtrip() throws {
        let now = Date.now
        let header = LowOverheadContainer.Header(timestamp: now,
                                                 sequenceNumber: 101)
        let payload = Data([1, 2, 3, 4])
        let loc = LowOverheadContainer(header: header,
                                       payload: [payload])

        // Encode.
        var buffer = Data(count: loc.getRequiredBytes())
        _ = try buffer.withUnsafeMutableBytes {
            try loc.serialize(into: $0)
        }

        // Decode.
        try buffer.withUnsafeBytes {
            let decoded = try LowOverheadContainer(encoded: $0)
            XCTAssertEqual(loc.header.timestamp, decoded.header.timestamp)
            XCTAssertEqual(loc.header.sequenceNumber, decoded.header.sequenceNumber)
            XCTAssertEqual(loc.payload, decoded.payload)
        }
    }
}
