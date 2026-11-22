import Darwin
import Foundation
import VerificationCore

enum SandboxPath {
    static func physical(_ url: URL) throws -> String {
        // realpath owns one initialized NUL-terminated allocation on success. Free it exactly once;
        // the pointer never escapes, and String materializes only at the sandbox profile boundary.
        guard let pointer = realpath(url.path, nil) else { throw InvarError("ISOLATION_UNAVAILABLE", "Cannot resolve the physical sandbox root", exitCode: 8) }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
