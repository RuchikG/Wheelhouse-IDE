import Foundation

/// Splits a language server's output stream into JSON-RPC message bodies and
/// frames outgoing ones (`Content-Length` header, blank line, body).
struct LanguageServerMessageFramer {
    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private var buffer = Data()

    /// Adds received bytes and returns every message completed by them.
    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        while let headerEnd = buffer.range(of: Self.headerTerminator) {
            let header = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
            guard let length = Self.contentLength(in: header) else {
                buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
                continue
            }
            guard buffer.distance(from: headerEnd.upperBound, to: buffer.endIndex) >= length else { break }
            let bodyEnd = buffer.index(headerEnd.upperBound, offsetBy: length)
            messages.append(Data(buffer[headerEnd.upperBound..<bodyEnd]))
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        }
        return messages
    }

    static func frame(_ body: Data) -> Data {
        var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        framed.append(body)
        return framed
    }

    private static func contentLength(in header: String) -> Int? {
        // Anything a remote shell printed before the server started ends up in
        // front of the first header; splitting on every line break steps over it.
        for line in header.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
               let length = Int(parts[1].trimmingCharacters(in: .whitespaces)), length >= 0 {
                return length
            }
        }
        return nil
    }
}
