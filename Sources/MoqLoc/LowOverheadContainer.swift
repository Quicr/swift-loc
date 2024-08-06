import Foundation
import QuicVarInt

enum LowOverheadContainerError: Error {
    case bufferTooSmall(Int)
    case failedToParse
}

public class LowOverheadContainer {
    public class Header {
        public struct Field {
            let shortname: String
            let description: String
            let id: Int
            let value: Data
        }

        public static let timestampTag: VarInt = 1
        public static let sequenceNumberTag: VarInt = 2
        public static let stopTag: VarInt = 3

        let timestamp: UInt64
        let sequenceNumber: UInt64
        private var fields: [Field] = []

        init(timestamp: Date, sequenceNumber: UInt64, since: Date = .init(timeIntervalSince1970: 0)) {
            self.timestamp = UInt64(timestamp.timeIntervalSince(since) * 1_000_000)
            self.sequenceNumber = sequenceNumber
        }

        init(timestampUs: UInt64, sequenceNumber: UInt64) {
            self.timestamp = timestampUs
            self.sequenceNumber = sequenceNumber
        }

        func addField(field: Field) {
            self.fields.append(field)
        }

        func getHeaderSize() -> Int {
            var headerSize = 0

            // Timestamp.
            headerSize += Self.timestampTag.encodedBitWidth / 8
            let actualTimestampSize = MemoryLayout.size(ofValue: self.timestamp)
            let encodedTimestampSize = VarInt(actualTimestampSize)
            headerSize += encodedTimestampSize.encodedBitWidth / 8
            headerSize += actualTimestampSize

            // Sequence number.
            headerSize += Self.sequenceNumberTag.encodedBitWidth / 8
            let actualSequenceSize = MemoryLayout.size(ofValue: self.sequenceNumber)
            let encodedSequenceSize = VarInt(actualSequenceSize)
            headerSize += encodedSequenceSize.encodedBitWidth / 8
            headerSize += actualSequenceSize

            // Stop.
            headerSize += Self.stopTag.encodedBitWidth / 8
            return headerSize
        }

        func serialize(into: UnsafeMutableRawBufferPointer) throws -> Int {
            let required = self.getHeaderSize()
            guard into.count >= required else {
                throw LowOverheadContainerError.bufferTooSmall(required)
            }
            var offset = 0

            // Timestamp.
            offset += try self.encodeTLV(into: into, tag: Self.timestampTag, value: self.timestamp)

            // Sequence.
            offset += try self.encodeTLV(into: into.advanced(offset),
                                         tag: Self.sequenceNumberTag,
                                         value: self.sequenceNumber)

            // TODO: Encode other fields.

            // Stop tag.
            try Self.stopTag.toWireFormat(into: into.advanced(offset))
            offset += Self.stopTag.encodedBitWidth / 8
            assert(offset == required)
            return offset
        }

        private func encodeTLV(into: UnsafeMutableRawBufferPointer, tag: VarInt, value: UInt64) throws -> Int {
            let tagSize = tag.encodedBitWidth / 8
            let size = MemoryLayout.size(ofValue: value)
            let encodedSize = VarInt(size)
            let required = tagSize + size + (encodedSize.encodedBitWidth / 8)
            assert(into.count >= required)
            // Tag (VarInt).
            try tag.toWireFormat(into: into)
            var index = tag.encodedBitWidth / 8

            // Length (VarInt).
            try encodedSize.toWireFormat(into: into.advanced(index))
            index += encodedSize.encodedBitWidth / 8

            // Value (UInt64).
            into.storeBytes(of: value, toByteOffset: index, as: UInt64.self)
            index += MemoryLayout.size(ofValue: value)
            assert(index == required)
            return index
        }
    }

    let header: Header
    let payload: [Data]

    init(header: Header, payload: [Data]) {
        self.header = header
        self.payload = payload
    }

    init(encoded: UnsafeRawBufferPointer) throws {
        var offset = 0

        var timestamp: UInt64?
        var sequenceNumber: UInt64?
        var payloads: [Data] = []

        while offset < encoded.count {
            // Extract tag.
            let tag = try VarInt(fromWire: encoded.advanced(offset))
            offset += tag.encodedBitWidth / 8
            guard tag != Header.stopTag else {
                break
            }

            // Extract length of value.
            let length = try VarInt(fromWire: encoded.advanced(offset))
            offset += length.encodedBitWidth / 8

            // Extract value.
            switch tag {
            case Header.timestampTag:
                let expectedSize = MemoryLayout<UInt64>.size
                assert(length == expectedSize)
                timestamp = encoded.loadUnaligned(fromByteOffset: offset, as: UInt64.self)

            case Header.sequenceNumberTag:
                let expectedSize = MemoryLayout<UInt64>.size
                assert(length == expectedSize)
                sequenceNumber = encoded.loadUnaligned(fromByteOffset: offset, as: UInt64.self)

            default:
                // TODO: Handle custom and unknown tags (via callback?).
                break
            }

            offset += Int(length)
        }

        while offset < encoded.count {
            let payloadLength = try VarInt(fromWire: encoded.advanced(offset))
            offset += payloadLength.encodedBitWidth / 8
            let payload = Data(bytes: encoded.advanced(offset).baseAddress!,
                               count: Int(payloadLength))
            payloads.append(payload)
            offset += Int(payloadLength)
        }

        guard let timestamp,
              let sequenceNumber,
              payloads.count > 0 else {
            throw LowOverheadContainerError.failedToParse
        }

        self.header = .init(timestampUs: timestamp, sequenceNumber: sequenceNumber)
        self.payload = payloads
    }

    func getRequiredBytes() -> Int {
        var required = self.header.getHeaderSize()
        for payload in self.payload {
            required += VarInt(payload.count).encodedBitWidth / 8
            required += payload.count
        }
        return required
    }

    func serialize(into: UnsafeMutableRawBufferPointer) throws -> Int {
        // Header.
        var offset = try self.header.serialize(into: into)

        // Payloads.
        for payload in self.payload {
            // Length.
            let size = VarInt(payload.count)
            try size.toWireFormat(into: into.advanced(offset))
            offset += size.encodedBitWidth / 8
            // Payload itself.
            into.advanced(offset).copyBytes(from: payload)
            offset += payload.count
        }
        return offset
    }
}

extension UnsafeRawBufferPointer {
    func advanced(_ offset: Int) -> UnsafeRawBufferPointer {
        assert(offset < self.count)
        return .init(start: self.baseAddress! + offset, count: self.count - offset)
    }
}

extension UnsafeMutableRawBufferPointer {
    func advanced(_ offset: Int) -> UnsafeMutableRawBufferPointer {
        assert(offset < self.count)
        return .init(start: self.baseAddress! + offset, count: self.count - offset)
    }
}
