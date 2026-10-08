// The key that signs Wheelhouse IDE's updates: an Ed25519 key in a file, in the form
// Sparkle's own tools read (the private key's 32 bytes, base64).
//   swift wheelhouse/update-key.swift new <key-file>            create the key, print its public half
//   swift wheelhouse/update-key.swift public <key-file>         print the public half
//   swift wheelhouse/update-key.swift sign <key-file> <archive> print the archive's signature
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("update-key: " + message + "\n").utf8))
    exit(1)
}

func key(at path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    else { fail("\(path) does not hold a signing key") }
    return key
}

func run() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch (arguments.first, arguments.count) {
    case ("new", 2):
        let path = arguments[1]
        let key = Curve25519.Signing.PrivateKey()
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Created for its owner only, and never over a key that is already there.
        let file = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard file >= 0 else { fail("\(path) could not be created: \(String(cString: strerror(errno)))") }
        let text = Data((key.rawRepresentation.base64EncodedString() + "\n").utf8)
        let written = text.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
        close(file)
        guard written == text.count else { fail("\(path) could not be written") }
        print(key.publicKey.rawRepresentation.base64EncodedString())
    case ("public", 2):
        print(key(at: arguments[1]).publicKey.rawRepresentation.base64EncodedString())
    case ("sign", 3):
        guard let archive = try? Data(contentsOf: URL(fileURLWithPath: arguments[2])) else {
            fail("\(arguments[2]) could not be read")
        }
        guard let signature = try? key(at: arguments[1]).signature(for: archive) else { fail("signing failed") }
        print(signature.base64EncodedString())
    default:
        fail("usage: update-key.swift new <key-file> | public <key-file> | sign <key-file> <archive>")
    }
}

// A declaration, so that the file also reads as a source file to the repository's checks.
let finished: Void = run()
