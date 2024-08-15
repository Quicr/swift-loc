import Foundation
import QuicVarInt

/// Possible errors that can be encountered when decoded a container.
public enum LowOverheadContainerError: Error {
    /// The provided buffer to decode into was too small. The required size is attached.
    case bufferTooSmall(Int)
    /// No container could be constructed from the given bitstream.
    case failedToParse
}

/// Low Overhead Media Container (LOC) per draft-mzanaty-moq-loc-03.
/// A LOC consists of a TLV based header and one or more payloads length prefixed payloads.
public class LowOverheadContainer {
    /// A LOC header consists of a series of TLV encoded fields.
    public class Header {
        /// A LOC header field, consisting of an ID and some data.
        public struct Field { // swiftlint:disable:this nesting
            /// Short name for the metadata. (Not sent on the wire.)
            let shortname: String
            /// Detailed description for the metadata. (Not sent on the wire.)
            let description: String
            /// Identifier assigned by the registry.
            let id: Int
            // Value of metadata.
            let value: Data
        }

        static let timestampTag: VarInt = 1
        static let sequenceNumberTag: VarInt = 2
        static let stopTag: VarInt = 3

        let microsecondsPerSecond: TimeInterval = 1_000_000
        /// This header's timestamp, in microseconds from epoch.
        public let timestamp: UInt64

        /// This header's timestamp, as a Date from epoch.
        public var date: Date {
            return Date(timeIntervalSince1970: TimeInterval(self.timestamp) / self.microsecondsPerSecond)
        }

        /// This header's sequence number.
        public let sequenceNumber: UInt64
        private var fields: [Field] = []

        /// Create a LOC header.
        /// - Parameters
        ///   - timestamp: Media capture timestamp.
        ///   - sequenceNumber: Media sequence number.
        ///   - since: Date to calculate encoded timestamp relative to. Defaults to unix epoch.
        public init(timestamp: Date, sequenceNumber: UInt64, since: Date = .init(timeIntervalSince1970: 0)) {
            self.timestamp = UInt64(timestamp.timeIntervalSince(since) * self.microsecondsPerSecond)
            self.sequenceNumber = sequenceNumber
        }

        /// Create a LOC header.
        /// - Parameters
        ///   - timestamp: Media capture timestamp in microseconds.
        ///   - sequenceNumber: Media sequence number.
        ///   - since: Date to calculate encoded timestamp relative to. Defaults to unix epoch.
        public init(timestampUs: UInt64, sequenceNumber: UInt64) {
            self.timestamp = timestampUs
            self.sequenceNumber = sequenceNumber
        }

        init(fromWire: UnsafeRawBufferPointer, noCopy: Bool, read: inout Int) throws {
            var offset = 0
            var timestamp: UInt64?
            var sequenceNumber: UInt64?
            while offset < fromWire.count - 1 {
                // Extract tag.
                let tag = try VarInt(fromWire: fromWire.advanced(offset))
                offset += tag.encodedBitWidth / 8

                // If this is the stop tag, stop.
                guard tag != Header.stopTag else {
                    break
                }

                // Extract length of value.
                let length = try VarInt(fromWire: fromWire.advanced(offset))
                offset += length.encodedBitWidth / 8

                // We should have enough space for the declared length.
                guard offset + Int(length) <= fromWire.count else {
                    throw LowOverheadContainerError.failedToParse
                }

                // Extract value.
                switch tag {
                case Header.timestampTag:
                    let expectedSize = MemoryLayout<UInt64>.size
                    assert(length == expectedSize)
                    timestamp = fromWire.loadUnaligned(fromByteOffset: offset, as: UInt64.self)

                case Header.sequenceNumberTag:
                    let expectedSize = MemoryLayout<UInt64>.size
                    assert(length == expectedSize)
                    sequenceNumber = fromWire.loadUnaligned(fromByteOffset: offset, as: UInt64.self)

                default:
                    // Custom fields.
                    let data: Data
                    if noCopy {
                        data = .init(bytesNoCopy: .init(mutating: try fromWire.advanced(offset).baseAddress!),
                                     count: Int(length),
                                     deallocator: .none)
                    } else {
                        data = .init(try fromWire.advanced(offset))
                    }
                    self.fields.append(.init(shortname: "", description: "", id: Int(tag), value: data))
                }

                offset += Int(length)
            }
            guard let timestamp,
                  let sequenceNumber else {
                throw LowOverheadContainerError.failedToParse
            }
            self.timestamp = timestamp
            self.sequenceNumber = sequenceNumber
            read = offset
        }

        /// Add a custom field to this header.
        public func addField(field: Field) {
            self.fields.append(field)
        }

        /// Retrieve a custom field from this header.
        /// - Parameter id: The identifier of the field to retrieve.
        /// - Returns The field or nil if not found.
        public func getField(id: Int) -> Field? {
            self.fields[id]
        }

        /// Return the size of the header when serialized.
        /// - Returns Size in bytes.
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

            // Other fields.
            for field in self.fields {
                headerSize += VarInt(field.id).encodedBitWidth / 8
                headerSize += VarInt(field.value.count).encodedBitWidth / 8
                headerSize += field.value.count
            }

            // Stop.
            headerSize += Self.stopTag.encodedBitWidth / 8
            return headerSize
        }

        /// Get the encoded representation of this header.
        /// - Parameter into: The buffer to serialize the header into.
        /// - Returns The number of bytes written into `into`.
        /// - throws `LowOverheadContainerError.bufferTooSmall` if the provided buffer is less than the required size.
        func serialize(into: UnsafeMutableRawBufferPointer) throws -> Int {
            let required = self.getHeaderSize()
            guard into.count >= required else {
                throw LowOverheadContainerError.bufferTooSmall(required)
            }
            var offset = 0

            // Timestamp.
            offset += self.encodeTLV(into: into,
                                     tag: Self.timestampTag,
                                     value: self.timestamp)

            // Sequence.
            offset += self.encodeTLV(into: try into.advanced(offset),
                                     tag: Self.sequenceNumberTag,
                                     value: self.sequenceNumber)

            // Other fields.
            for field in self.fields {
                try field.value.withUnsafeBytes {
                    offset += self.encodeTLV(into: try into.advanced(offset),
                                             tag: VarInt(field.id),
                                             value: $0)
                }
            }

            // Stop tag.
            try! Self.stopTag.toWireFormat(into: into.advanced(offset)) // swiftlint:disable:this force_try
            offset += Self.stopTag.encodedBitWidth / 8
            assert(offset == required)
            return offset
        }

        // Bounds checking should be enforced by classers, so:
        // swiftlint:disable force_try
        private func encodeTLV(into: UnsafeMutableRawBufferPointer, tag: VarInt, value: UInt64) -> Int {
            let tagSize = tag.encodedBitWidth / 8
            let size = MemoryLayout.size(ofValue: value)
            let encodedSize = VarInt(size)
            let required = tagSize + size + (encodedSize.encodedBitWidth / 8)
            assert(into.count >= required)
            // Tag (VarInt).
            try! tag.toWireFormat(into: into)
            var index = tag.encodedBitWidth / 8

            // Length (VarInt).
            try! encodedSize.toWireFormat(into: into.advanced(index))
            index += encodedSize.encodedBitWidth / 8

            // Value (UInt64).
            into.storeBytes(of: value, toByteOffset: index, as: UInt64.self)
            index += MemoryLayout.size(ofValue: value)
            assert(index == required)
            return index
        }

        private func encodeTLV(into: UnsafeMutableRawBufferPointer,
                               tag: VarInt,
                               value: UnsafeRawBufferPointer) -> Int {
            let tagSize = tag.encodedBitWidth / 8
            let encodedSize = VarInt(value.count)
            let required = tagSize + value.count + (encodedSize.encodedBitWidth / 8)
            assert(into.count >= required)
            try! tag.toWireFormat(into: into)
            var index = tag.encodedBitWidth / 8
            try! encodedSize.toWireFormat(into: into.advanced(index))
            index += encodedSize.encodedBitWidth / 8
            into.copyMemory(from: value)
            index += value.count
            assert(index == required)
            return index
        }
        // swiftlint:enable force_try
    }

    /// The LOC header.
    public let header: Header
    /// The LOC payload(s).
    public let payload: [Data]

    /// Create a new LOC to serialization.
    /// - Parameters
    ///     - header: LOC header.
    ///     - payload: Payloads for the container.
    public init(header: Header, payload: [Data]) {
        self.header = header
        self.payload = payload
    }

    /// Decode a LOC from serialized bytes.
    /// - Parameters:
    ///     - encoded: Pointer to encoded LOC bytes.
    ///     - noCopy: True if the LOC should use all memory in place, false to copy.
    ///     The caller must ensure this memory is valid for the lifetime of the LOC instance if this is enabled.
    public init(encoded: UnsafeRawBufferPointer, noCopy: Bool) throws {
        var offset = 0
        do {
            self.header = try .init(fromWire: encoded, noCopy: noCopy, read: &offset)
        } catch BufferError.boundsError {
            throw LowOverheadContainerError.failedToParse
        }

        var payloads: [Data] = []
        while offset < encoded.count - 1 {
            let payloadLength = try VarInt(fromWire: encoded.advanced(offset))
            if payloadLength == 0 {
                // Payload lengths are not allowed, assume we're done.
                break
            }
            offset += payloadLength.encodedBitWidth / 8
            guard offset + Int(payloadLength) <= encoded.count else {
                // There is not enough space for the declared length.
                // It might be a false positive VarInt beyond the edge of the LOC.
                // Unwind and stop.
                offset -= payloadLength.encodedBitWidth / 8
                break
            }
            let payload: Data
            let dataPtr = try! encoded.advanced(offset) // swiftlint:disable:this force_try
            if noCopy {
                payload = Data(bytesNoCopy: .init(mutating: dataPtr.baseAddress!),
                               count: Int(payloadLength),
                               deallocator: .none)
            } else {
                payload = Data(bytes: dataPtr.baseAddress!,
                               count: Int(payloadLength))
            }
            payloads.append(payload)
            offset += Int(payloadLength)
        }
        self.payload = payloads
    }

    /// Return the number of bytes this LOC instance will take up when serialized.
    /// - Returns Size in bytes.
    public func getRequiredBytes() -> Int {
        var required = self.header.getHeaderSize()
        for payload in self.payload {
            required += VarInt(payload.count).encodedBitWidth / 8
            required += payload.count
        }
        return required
    }

    /// Serialize the LOC into the provided buffer.
    /// - Parameter into: The buffer to write into.
    /// - Returns The number of bytes written.
    public func serialize(into: UnsafeMutableRawBufferPointer) throws -> Int {
        // Header.
        var offset = try self.header.serialize(into: into)

        // Payloads.
        for payload in self.payload {
            // Length.
            let size = VarInt(payload.count)
            try size.toWireFormat(into: into.advanced(offset))
            offset += size.encodedBitWidth / 8
            // Payload itself.
            try into.advanced(offset).copyBytes(from: payload)
            offset += payload.count
        }
        return offset
    }
}

enum BufferError: Error {
    case boundsError
}

extension UnsafeRawBufferPointer {
    func advanced(_ offset: Int) throws -> UnsafeRawBufferPointer {
        guard offset < self.count else {
            throw BufferError.boundsError
        }
        return .init(start: self.baseAddress!.advanced(by: offset), count: self.count - offset)
    }
}

extension UnsafeMutableRawBufferPointer {
    func advanced(_ offset: Int) throws -> UnsafeMutableRawBufferPointer {
        guard offset < self.count else {
            throw BufferError.boundsError
        }
        return .init(start: self.baseAddress!.advanced(by: offset), count: self.count - offset)
    }
}
