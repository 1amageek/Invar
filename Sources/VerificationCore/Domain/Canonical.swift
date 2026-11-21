import CryptoKit
import Foundation

public enum Canonical {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public static func identity<T: Encodable>(_ value: T) throws -> String { digest(try encode(value)) }
    public static func parts(_ domain: String,_ values: [String]) -> String {
        var hash = SHA256()
        for value in [domain] + values {
            let bytes = Data(value.utf8)
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { hash.update(bufferPointer: $0) }
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x",$0) }.joined()
    }
    public static func date() -> String { ISO8601DateFormatter().string(from: Date()) }
    public static func relative(_ path: String) throws -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.utf8.contains(0) }) else { throw InvarError("ARTIFACT_OUTSIDE_ROOT", "Expected a normalized relative path: \(path)", exitCode: 8) }
        return path
    }
}
