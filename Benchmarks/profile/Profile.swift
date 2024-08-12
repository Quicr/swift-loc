import Benchmark
import MoqLoc
import Foundation

let benchmarks = {
    Benchmark("Encode") { benchmark in
        let now = Date.now
        var seq: UInt64 = 0
        let data: Data = .init([0, 1, 2, 3])
        var buffer: UnsafeMutableRawBufferPointer?
        for _ in benchmark.scaledIterations {
            seq += 1
            let loc = LowOverheadContainer(header: .init(timestamp: now, sequenceNumber: seq), payload: [data])
            if buffer == nil {
                buffer = .allocate(byteCount: loc.getRequiredBytes(), alignment: MemoryLayout<UInt8>.alignment)
            }
            _ = try! loc.serialize(into: buffer!)
        }
    }

    Benchmark("Decode") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Date()) // replace this line with your own benchmark
        }
    }
}
