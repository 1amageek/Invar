import Foundation
import VerificationCore

struct FixedInputReader {
    static func inventory(_ context: BackendContext) throws -> ScopeInventory {
        let path = context.inputRoot.deletingLastPathComponent().appendingPathComponent("inventory.json")
        let bytes = try read(path,maximum: 64 * 1024 * 1024)
        let inventory = try JSONDecoder().decode(ScopeInventory.self,from: bytes)
        let reference = try VerificationInput.reference(inventory)
        guard reference == context.input else { throw InvarError("INPUT_MISMATCH","Worker graph differs from fixed input reference") }
        return inventory
    }
    static func oracle(_ context: BackendContext) throws -> Data {
        guard let entry = context.job.oracle else { throw InvarError("INPUT_UNAVAILABLE","No fixed oracle/corpus reference") }
        let bytes = try read(context.inputRoot.appendingPathComponent(entry.path),maximum: min(entry.byteCount,5 * 1024 * 1024))
        guard entry.byteCount == bytes.count, Canonical.digest(bytes) == entry.digest else { throw InvarError("INPUT_MISMATCH","Fixed oracle/corpus bytes changed") }
        return bytes
    }
    static func read(_ path: URL,maximum: Int) throws -> Data {
        guard maximum >= 0, path.resolvingSymlinksInPath().path == path.standardizedFileURL.path else { throw InvarError("INPUT_MISMATCH","Fixed input contains a symbolic path") }
        let handle = try FileHandle(forReadingFrom: path)
        do {
            let bytes = try handle.read(upToCount: maximum + 1) ?? Data()
            guard bytes.count <= maximum else { throw InvarError("RESOURCE_LIMIT","Fixed input exceeds read budget",exitCode: 6) }
            try handle.close(); return bytes
        } catch {
            do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Fixed input read failed (\(error)); close failed (\(cleanup))") }
            throw error
        }
    }
}
