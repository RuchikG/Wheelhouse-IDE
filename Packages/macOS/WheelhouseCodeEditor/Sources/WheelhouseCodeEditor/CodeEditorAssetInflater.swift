import Foundation
import zlib

/// Inflates the zlib-deflated `.js`/`.mjs` assets the app build produces.
enum CodeEditorAssetInflater {
    static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        return data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Data? in
            guard let base = input.bindMemory(to: Bytef.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)

            var output = Data()
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let capacity = chunk.count
                let status = chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(capacity)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let produced = capacity - Int(stream.avail_out)
                output.append(chunk, count: produced)
                if status == Z_STREAM_END { return output }
                if status != Z_OK || (stream.avail_in == 0 && produced == 0) { return nil }
            }
        }
    }
}
