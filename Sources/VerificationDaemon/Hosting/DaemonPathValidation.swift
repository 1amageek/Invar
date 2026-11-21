import Darwin
import Foundation
import VerificationCore

public enum DaemonPathValidation {
    public static func canonical(_ path: URL) throws -> URL {
        var ancestor = path.standardizedFileURL, missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path) {
            guard ancestor.path != "/" else { throw InvarError("INVALID_STATE_ROOT","State root has no existing parent",exitCode: 2) }
            missing.append(ancestor.lastPathComponent); ancestor.deleteLastPathComponent()
        }
        // realpath returns one owned allocation. Copy it once and free in this
        // scope; no pointer or borrowed bytes escape into the returned URL.
        guard let pointer = ancestor.path.withCString({ realpath($0,nil) }) else { throw InvarError("INVALID_STATE_ROOT","Cannot resolve state-root parent",exitCode: 2) }
        let resolved = String(cString: pointer); free(pointer)
        var result = URL(fileURLWithPath: resolved)
        for component in missing.reversed() { result.appendPathComponent(component) }
        return result
    }
    public static func stateRoot(_ state: URL,outside workspace: URL) throws -> URL {
        let source = try canonical(workspace), destination = try canonical(state)
        guard source.path != destination.path, !destination.path.hasPrefix(source.path + "/") else { throw InvarError("INVALID_STATE_ROOT","Invar state must remain outside the indexed workspace",exitCode: 2) }
        return destination
    }
}
