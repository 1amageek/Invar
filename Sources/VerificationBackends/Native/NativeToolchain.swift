import CryptoKit
import Darwin
import Foundation
import VerificationCore

public enum NativeToolchain {
    public static func configurationIdentity(_ profile: NativeProfile) throws -> String {
        try PlanValidation.profile(profile)
        return try Canonical.identity(["kind": profile.kind, "compiler": profile.compiler, "sdk": profile.sdk, "tools": profile.toolsDirectory, "target": profile.target])
    }
    public static func identity(_ profile: NativeProfile) throws -> String {
        try PlanValidation.profile(profile)
        let compiler = URL(fileURLWithPath: profile.compiler).standardizedFileURL.resolvingSymlinksInPath()
        let tools = URL(fileURLWithPath: profile.toolsDirectory).standardizedFileURL.resolvingSymlinksInPath()
        let sdk = URL(fileURLWithPath: profile.sdk).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: compiler.path), FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent("ld").path),
            FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { throw InvarError("BLOCKED_NATIVE_TOOLCHAIN", "Explicit compiler/linker/sandbox runtime unavailable", exitCode: 3) }
        let roots = try Set([toolchainRoot(compiler), toolchainRoot(tools), sdk]).sorted { $0.path < $1.path }
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        var hasher = SHA256(), count = 0, total: UInt64 = 0
        let header = try Canonical.encode(["profile": profile.kind, "target": profile.target, "compiler": compiler.path, "invokedCompiler": profile.compiler, "tools": tools.path, "sdk": sdk.path, "os": ProcessInfo.processInfo.operatingSystemVersionString])
        hasher.update(data: header)
        for root in roots {
            var enumerationFailure: Error?
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in enumerationFailure = error; return false }) else { throw InvarError("INPUT_UNAVAILABLE", "Cannot inventory native environment") }
            var paths: [String] = []
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                // Enumerator URLs may use /private/var while the root uses /var.
                let level = enumerator.level
                guard level > 0, level < url.pathComponents.count else { throw InvarError("INPUT_UNAVAILABLE", "Native inventory returned an invalid traversal depth") }
                let path = url.pathComponents.suffix(level).joined(separator: "/")
                count += 1
                guard count <= 250000, ContinuousClock.now < deadline else { throw InvarError("RESOURCE_LIMIT", "Native environment inventory exceeded count/time budget", exitCode: 6) }
                paths.append(path)
            }
            if let enumerationFailure { throw InvarError("INPUT_UNAVAILABLE", "Native environment inventory could not read every entry: \(enumerationFailure)") }
            for relative in paths.sorted() {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw InvarError("RESOURCE_LIMIT", "Native environment inventory exceeded time budget", exitCode: 6) }
                let path = root.appendingPathComponent(relative), attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                let type = attributes[.type] as? FileAttributeType
                let mode = (attributes[.posixPermissions] as? NSNumber)?.uint64Value ?? 0
                hasher.update(data: Data((root.path + "/" + relative + ":" + String(mode) + ":" + (type?.rawValue ?? "unknown") + "\n").utf8))
                if type == .typeSymbolicLink {
                    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: path.path)
                    let resolved = path.resolvingSymlinksInPath()
                    guard roots.contains(where: { resolved.path == $0.path || resolved.path.hasPrefix($0.path + "/") }) else { throw InvarError("UNSUPPORTED_NATIVE_PROFILE", "Native environment contains an undeclared external symlink", exitCode: 3) }
                    hasher.update(data: Data(destination.utf8)); continue
                }
                if type == .typeDirectory { continue }
                guard type == .typeRegular else { throw InvarError("UNSUPPORTED_NATIVE_PROFILE", "Native environment contains a non-regular artifact", exitCode: 3) }
                let handle = try FileHandle(forReadingFrom: path)
                do {
                    while true {
                        try Task.checkCancellation()
                        let bytes = try autoreleasepool { try handle.read(upToCount: 1_048_576) ?? Data() }
                        if bytes.isEmpty { break }
                        total += UInt64(bytes.count)
                        guard total <= 16 * 1024 * 1024 * 1024, ContinuousClock.now < deadline else { throw InvarError("RESOURCE_LIMIT", "Native environment inventory exceeded byte/time budget", exitCode: 6) }
                        hasher.update(data: bytes)
                    }
                    try handle.close()
                } catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED", "Inventory failed (\(error)); close failed (\(cleanup))") }; throw error }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func toolchainRoot(_ path: URL) throws -> URL {
        var value = path
        while value.path != "/" {
            if value.pathExtension == "xctoolchain" { return value }
            value.deleteLastPathComponent()
        }
        throw InvarError("UNSUPPORTED_NATIVE_PROFILE", "Expected an explicitly installed xctoolchain", exitCode: 3)
    }
}
