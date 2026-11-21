import Darwin
import Foundation
import VerificationCore

struct NativeSandbox {
    static func profile(_ profile: NativeProfile, work: URL, build: Bool) throws -> String {
        let compiler = URL(fileURLWithPath: profile.compiler).standardizedFileURL.resolvingSymlinksInPath()
        let compilerRoot = try NativeToolchain.toolchainRoot(compiler)
        let toolsRoot = try NativeToolchain.toolchainRoot(URL(fileURLWithPath: profile.toolsDirectory))
        let sdk = URL(fileURLWithPath: profile.sdk).standardizedFileURL.resolvingSymlinksInPath()
        guard sdk.pathExtension == "sdk", FileManager.default.fileExists(atPath: sdk.appendingPathComponent("SDKSettings.json").path) else { throw InvarError("UNSUPPORTED_NATIVE_PROFILE", "Expected an installed Apple SDK root", exitCode: 3) }
        let runtime = work.appendingPathComponent("runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let physicalWork = try physical(work), physicalRuntime = try physical(runtime)
        var read = [physicalWork, "/System/Library", "/System/Cryptexes", "/System/Volumes/Preboot", "/System/Volumes/iSCPreboot", "/usr/lib", "/usr/share", "/Library/Apple", "/private/var/db/dyld", "/private/preboot", compilerRoot.appendingPathComponent("usr/lib").path]
        if build { read += [compilerRoot.path, toolsRoot.path, sdk.path, "/bin", "/usr/bin"] }
        var result = "(version 1)\n(deny default)\n(allow sysctl-read)\n(allow file-read-metadata)\n(allow file-read* (literal \"/\") (literal \"/dev/null\") (literal \"/dev/random\") (literal \"/dev/urandom\"))\n"
        var ancestors = Set<String>()
        for path in read {
            var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            while parent.path != "/" { ancestors.insert(parent.path); parent.deleteLastPathComponent() }
        }
        for path in ancestors.sorted() { result += "(allow file-read* (literal \(try literal(path))))\n" }
        for path in Set(read).sorted() { result += "(allow file-read* file-map-executable (subpath \(try literal(path))))\n" }
        let writable = build ? physicalWork : physicalRuntime
        result += "(allow file-write* (subpath \(try literal(writable))) (literal \"/dev/null\"))\n"
        if build { result += "(allow process-fork)\n(allow process-exec (subpath \(try literal(compilerRoot.path))) (subpath \(try literal(toolsRoot.path))) (literal \"/usr/bin/xcrun\") (literal \"/bin/sh\"))\n" }
        else { result += "(allow process-exec (literal \(try literal(physicalWork + "/harness"))))\n" }
        return result
    }
    private static func physical(_ url: URL) throws -> String {
        // realpath owns one initialized NUL-terminated allocation on success. Free it exactly once;
        // the pointer never escapes, and String materializes only at the sandbox profile boundary.
        guard let pointer = realpath(url.path, nil) else { throw InvarError("ISOLATION_UNAVAILABLE", "Cannot resolve the physical sandbox root", exitCode: 8) }
        defer { free(pointer) }
        return String(cString: pointer)
    }
    private static func literal(_ value: String) throws -> String {
        guard value.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { throw InvarError("UNSUPPORTED_NATIVE_PROFILE", "Sandbox paths must be printable ASCII", exitCode: 3) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        let bytes = try encoder.encode(value)
        return String(decoding: bytes, as: UTF8.self)
    }
}
