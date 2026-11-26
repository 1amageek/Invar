import Foundation
import VerificationCore

struct ProjectSandbox {
    static let executable = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

    static func install(at work: URL, tools: [String], validating: Bool = false) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw InvarError("ISOLATION_UNAVAILABLE", "The project command sandbox is unavailable", exitCode: 8)
        }
        let attempt = try SandboxPath.physical(work)
        let installedTools = try tools.map { path in
            let physical = try SandboxPath.physical(URL(fileURLWithPath: path))
            return URL(fileURLWithPath: physical)
        }
        let toolDirectories = installedTools.flatMap { tool -> [String] in
            let directory = tool.deletingLastPathComponent()
            if directory.lastPathComponent == "bin" {
                let prefix = directory.deletingLastPathComponent()
                let versions = prefix.deletingLastPathComponent()
                if versions.lastPathComponent == "Versions", versions.deletingLastPathComponent().pathExtension == "framework" {
                    return [prefix.path]
                }
                return [directory.path] + ["lib", "libexec", "share"].map { prefix.appendingPathComponent($0).path }
            }
            if tool.lastPathComponent == "formal" {
                let resources = directory.appendingPathComponent("toolchain").path
                let bundles = ["swift-formal_FormalCompiler.bundle", "swift-formal_FormalValidation.bundle"]
                return [resources] + bundles.map { directory.appendingPathComponent($0).path }
            }
            return []
        }
        let system = ["/System/Library", "/System/Cryptexes", "/System/Volumes/Preboot", "/usr/lib",
                      "/usr/share", "/Library/Apple", "/private/var/db/dyld", "/private/preboot",
                      "/bin", "/usr/bin", "/Applications/Xcode.app/Contents/Developer",
                      "/Applications/Xcode.app/Contents/Frameworks", "/Applications/Xcode.app/Contents/SharedFrameworks"]
        var policy = """
            (version 1)
            (deny default)
            (allow sysctl-read file-read-metadata process-fork)
            (allow file-read* (literal "/") (literal "/dev/null") (literal "/dev/zero") (literal "/dev/random") (literal "/dev/urandom")
                (literal "/Applications/Xcode.app/Contents/Info.plist"))

            """
        if installedTools.contains(where: { $0.lastPathComponent == "java" }) {
            // The JVM uses libinfo to initialize the current user even during an offline check.
            policy += "(allow mach-lookup (global-name \"com.apple.system.opendirectoryd.libinfo\"))\n"
        }
        let javaConfigurations = Set(installedTools.filter {
            $0.lastPathComponent == "java" && $0.deletingLastPathComponent().lastPathComponent == "bin"
        }.map { $0.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("conf").path })
        var ancestors = Set<String>()
        let directories = Set(toolDirectories + system + [attempt])
        for root in directories.union(javaConfigurations).union(installedTools.map(\.path)) {
            var parent = URL(fileURLWithPath: root).deletingLastPathComponent()
            while parent.path != "/" {
                ancestors.insert(parent.path)
                parent.deleteLastPathComponent()
            }
        }
        for root in directories.sorted() {
            policy += "(allow file-read* file-map-executable (subpath \(try literal(root))))\n"
        }
        for path in javaConfigurations.sorted() {
            policy += "(allow file-read* (subpath \(try literal(path))))\n"
        }
        for path in ancestors.sorted() { policy += "(allow file-read* (literal \(try literal(path))))\n" }
        for tool in installedTools {
            policy += "(allow file-read* file-map-executable process-exec (literal \(try literal(tool.path))))\n"
        }
        for path in ["/usr/bin", "/bin", "/Applications/Xcode.app/Contents/Developer"] + toolDirectories.sorted() {
            policy += "(allow process-exec (subpath \(try literal(path))))\n"
        }
        let writable = validating ? ["validation", "home", "tmpdir"] : ["workspace", "home", "tmpdir"]
        for folder in writable {
            policy += "(allow file-write* (subpath \(try literal(attempt + "/" + folder))))\n"
        }
        policy += "(allow file-write* (literal \"/dev/null\"))\n"
        let file = work.appendingPathComponent(validating ? "validator.sb" : "project.sb")
        try Data(policy.utf8).write(to: file,options: .withoutOverwriting)
        return file
    }

    private static func literal(_ path: String) throws -> String {
        guard path.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else {
            throw InvarError("INVALID_CONFIGURATION", "Control characters are unsupported in sandbox paths", exitCode: 2)
        }
        return "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
