import Foundation
import FormalValidation
import VerificationCore

struct SetupTools {
    let root: URL

    private let files = FileManager.default
    private static let stitchVersion = "0.2.0"
    private static let pythonVersion = "3.12.14"

    func formal(workspace: URL) async throws -> [String: String] {
        let tools = try await formalRuntime()
        let tlc = try await archive(
            "tlc-1.8.0.jar",
            url: "https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar",
            digest: "df7cef5d37bcca879817424c001696e07fd094d68a72690449af3045fd972469"
        )
        let projectPin = workspace.appendingPathComponent("lean-toolchain")
        var lean = tools.lean
        if files.fileExists(atPath: projectPin.path) {
            let pin = try String(contentsOf: projectPin, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if pin != "leanprover/lean4:v" + tools.policy.lean.version {
                lean = try await leanRelease(pin)
            }
        }
        return ["formalToolchain": tools.root.path, "java": tools.java.path, "tlc": tlc.path,
                "lean": lean.path, "lake": lean.deletingLastPathComponent().appendingPathComponent("lake").path]
    }

    func formalCLI() async throws -> [String: String] {
        let binary = try await mintInstall(repository: "swift-formal", product: "formal",
                                           revision: "ebb993c910d3808947a6b6ea5429e5b31944923e")
        let runtime = binary.deletingLastPathComponent().appendingPathComponent("toolchain")
        if !files.fileExists(atPath: runtime.path) {
            let tools = try await formalRuntime()
            let snapshot = runtime.deletingLastPathComponent().appendingPathComponent(".tools-" + UUID().uuidString)
            defer { if files.fileExists(atPath: snapshot.path) { clean(snapshot) } }
            _ = try await invoke(URL(fileURLWithPath: "/bin/cp"), ["-cR", tools.root.path, snapshot.path], timeout: 300)
            try files.moveItem(at: snapshot, to: runtime)
        }
        let observed = try await invoke(binary, ["--version"])
        guard observed == "formal 0.1.1" else { throw failure("Expected formal 0.1.1, found \(observed)") }
        _ = try await invoke(binary, ["toolchain"], timeout: 60)
        return ["formal": binary.path]
    }

    private func formalRuntime() async throws -> BundledToolchain {
        let policy = try ToolchainPolicy.bundled()
        let inventory = root.appendingPathComponent("formal-" + policy.inventorySHA256)
        let verifier = PinnedToolchain()
        let tools: BundledToolchain
        if files.fileExists(atPath: inventory.path) {
            tools = try verifier.verify(at: inventory)
        } else {
            tools = try await verifier.prepare(at: inventory, cache: root.appendingPathComponent("formal-downloads"))
        }
        return tools
    }

    func deslop() async throws -> [String: String] {
        let version = "1.0.1"
        let revision = "05f1033316150f0d935237e362b38b7bce7d52fa"
        let destination = root.appendingPathComponent("deslop-" + version)
        if !files.isExecutableFile(atPath: destination.path) {
            let built = try await mintInstall(repository: "deslop", product: "deslop", revision: revision)
            try files.copyItem(at: built, to: destination)
        }
        let observed = try await invoke(destination, ["--version"])
        guard observed == version else { throw failure("Expected deslop \(version), found \(observed)") }
        return ["deslop": destination.path]
    }

    func stitch() async throws -> [String: String] {
        let uv = try await executableArchive(
            "uv-0.12.5",
            url: "https://github.com/astral-sh/uv/releases/download/0.12.5/uv-aarch64-apple-darwin.tar.gz",
            digest: "5bb0e5fe008a773c3dbcb97ff79cd89e1241464fe9d2f986d52ad8f1b037bd62",
            member: "uv-aarch64-apple-darwin/uv"
        )
        let environment = ["PATH": "/usr/bin:/bin", "HOME": files.homeDirectoryForCurrentUser.path,
                           "UV_PYTHON_INSTALL_DIR": root.appendingPathComponent("python").path,
                           "UV_CACHE_DIR": root.appendingPathComponent("uv-cache").path,
                           "UV_NO_CONFIG": "1"]
        let venv = root.appendingPathComponent("stitch-\(Self.stitchVersion)-python-\(Self.pythonVersion)")
        let python = venv.appendingPathComponent("bin/python")
        let stitch = venv.appendingPathComponent("bin/stitch")
        if !files.isExecutableFile(atPath: stitch.path) {
            let wheel = try await archive(
                "stitch_fuzz-0.2.0-py3-none-any.whl",
                url: "https://files.pythonhosted.org/packages/eb/cc/1482f34475bcbf38422034576c163f2579d158e0f0b434a804c54e560b2b/stitch_fuzz-0.2.0-py3-none-any.whl",
                digest: "e5bd52699d18031cb49b752d16169a11d5b101b3b1ff2505a176ebc75514ee1d"
            )
            if !files.isExecutableFile(atPath: python.path) {
                _ = try await invoke(uv, ["venv", "--managed-python", "--python", Self.pythonVersion, venv.path],
                                     timeout: 600, environment: environment)
            }
            _ = try await invoke(uv, ["pip", "install", "--python", python.path, "--no-index", "--no-deps", wheel.path],
                                 timeout: 120, environment: environment)
        }
        let observedPython = try await invoke(python, ["--version"])
        let observedStitch = try await invoke(stitch, ["--version"])
        guard observedPython == "Python " + Self.pythonVersion, observedStitch == "stitch-fuzz " + Self.stitchVersion else {
            throw failure("Unexpected Python or STITCH++ version in the managed environment")
        }
        return ["python": python.path, "stitch": stitch.path]
    }

    func prepareStitchImage(_ stitch: String, language: String) async throws -> String {
        let docker = try executable("docker", hint: "Install and start a local Docker-compatible engine")
        let context = try await invoke(docker, ["context", "show"])
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "DOCKER_HOST")
        environment["DOCKER_CONTEXT"] = context
        let address = try await invoke(docker, ["context", "inspect", context, "--format", "{{.Endpoints.docker.Host}}"],
                                       environment: environment)
        guard address.hasPrefix("unix://") else { throw failure("Select a local Docker context") }
        do {
            _ = try await invoke(docker, ["version", "--format", "{{.Server.Version}}"], environment: environment)
        } catch is CancellationError { throw CancellationError() }
        catch { throw failure("Start the local Docker engine and retry setup: \(error)") }
        let output = try await invoke(URL(fileURLWithPath: stitch), ["setup", "--lang", language],
                                      timeout: 900, environment: environment)
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("ready: base image ") }) else {
            throw failure("STITCH++ did not identify its prepared \(language) image")
        }
        return String(line.dropFirst("ready: base image ".count))
    }

    private func leanRelease(_ pin: String) async throws -> URL {
        guard pin.wholeMatch(of: /leanprover\/lean4:v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?/) != nil else {
            throw failure("Expected an exact Lean release in lean-toolchain, found \(pin)")
        }
        let installer = try await executableArchive(
            "elan-init-4.4.0",
            url: "https://github.com/leanprover/elan/releases/download/v4.4.0/elan-aarch64-apple-darwin.tar.gz",
            digest: "27af24edeace839730e8c9119783f12d5f694327d4771605021ca09db1ab0a87",
            member: "elan-init"
        )
        // Elan selects installer mode from argv[0].
        let initDirectory = root.appendingPathComponent("elan-installer-4.4.0")
        try files.createDirectory(at: initDirectory, withIntermediateDirectories: true)
        let entry = initDirectory.appendingPathComponent("elan-init")
        if !files.fileExists(atPath: entry.path) { try files.createSymbolicLink(at: entry, withDestinationURL: installer) }
        let home = root.appendingPathComponent("elan")
        let elan = home.appendingPathComponent("bin/elan")
        var environment = ["PATH": "/usr/bin:/bin", "HOME": files.homeDirectoryForCurrentUser.path, "ELAN_HOME": home.path]
        if !files.isExecutableFile(atPath: elan.path) {
            _ = try await invoke(entry, ["-y", "--default-toolchain", "none", "--no-modify-path"],
                                 timeout: 120, environment: environment)
        }
        _ = try await invoke(elan, ["toolchain", "install", pin], timeout: 900, environment: environment)
        environment["ELAN_TOOLCHAIN"] = pin
        let path = try await invoke(elan, ["which", "lean"], environment: environment)
        guard path.hasPrefix(home.path + "/"), files.isExecutableFile(atPath: path) else {
            throw failure("Managed Lean executable is unavailable for \(pin)")
        }
        return URL(fileURLWithPath: path)
    }

    private func executableArchive(_ name: String, url: String, digest: String, member: String) async throws -> URL {
        let destination = root.appendingPathComponent(name)
        if files.isExecutableFile(atPath: destination.path) { return destination }
        let data = try await archive(name + ".tar.gz", url: url, digest: digest)
        let scratch = root.appendingPathComponent(".extract-" + UUID().uuidString)
        try files.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { clean(scratch) }
        _ = try await invoke(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", data.path, "-C", scratch.path, member])
        let file = scratch.appendingPathComponent(member)
        guard files.isExecutableFile(atPath: file.path) else { throw failure("Missing executable in \(name) archive") }
        try files.moveItem(at: file, to: destination)
        return destination
    }

    private func archive(_ name: String, url: String, digest: String) async throws -> URL {
        let destination = root.appendingPathComponent(name)
        if files.fileExists(atPath: destination.path) {
            guard try FileDigest.sha256(destination) == digest else { throw failure("Digest mismatch for \(name)") }
            return destination
        }
        let temporary = root.appendingPathComponent(".download-" + UUID().uuidString)
        defer { if files.fileExists(atPath: temporary.path) { clean(temporary) } }
        _ = try await invoke(URL(fileURLWithPath: "/usr/bin/curl"),
                             ["--disable", "--fail", "--silent", "--show-error", "--location", "--proto", "=https",
                              "--proto-redir", "=https", "--max-time", "600", "--output", temporary.path, url], timeout: 610)
        guard try FileDigest.sha256(temporary) == digest else { throw failure("Digest mismatch for \(name)") }
        try files.moveItem(at: temporary, to: destination)
        return destination
    }

    private func mintInstall(repository: String, product: String, revision: String) async throws -> URL {
        let path = root.appendingPathComponent("mint/packages/github.com_1amageek_\(repository)/build/\(revision)/\(product)")
        if files.isExecutableFile(atPath: path.path) { return path }
        let mint = try executable("mint", hint: "Install Invar with Mint to prepare Swift verification tools")
        var environment = ProcessInfo.processInfo.environment
        environment["MINT_PATH"] = root.appendingPathComponent("mint").path
        environment["MINT_LINK_PATH"] = root.appendingPathComponent("mint-bin").path
        _ = try await invoke(mint, ["install", "1amageek/\(repository)@" + revision, product, "--no-link"],
                             timeout: 1800, environment: environment)
        guard files.isExecutableFile(atPath: path.path) else { throw failure("Mint did not install \(product)") }
        return path
    }

    private func executable(_ name: String, hint: String) throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") where directory.hasPrefix("/") {
            let file = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if files.isExecutableFile(atPath: file.path) { return file }
        }
        throw failure(hint)
    }

    private func invoke(_ tool: URL, _ arguments: [String], timeout: Double = 20,
                        environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> String {
        let log = root.appendingPathComponent(".setup-" + UUID().uuidString)
        defer {
            for suffix in ["stdout", "stderr"] {
                let path = log.appendingPathExtension(suffix)
                if files.fileExists(atPath: path.path) { clean(path) }
            }
        }
        let result = try await LocalToolRunner().run(executable: tool, arguments: arguments, directory: root,
                                                    environment: environment, log: log, timeout: timeout)
        guard result.exitCode == 0 else {
            let detail = (result.standardError.isEmpty ? result.standardOutput : result.standardError).suffix(2000)
            throw failure("\(tool.lastPathComponent) exited \(result.exitCode): \(detail)")
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clean(_ url: URL) {
        do { try files.removeItem(at: url) }
        catch { FileHandle.standardError.write(Data("Tool setup cleanup failed: \(error)\n".utf8)) }
    }

    private func failure(_ message: String) -> InvarError {
        InvarError("TOOL_SETUP_FAILED", message, exitCode: 6)
    }
}
