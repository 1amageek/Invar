import Foundation
import FormalCore
import FormalValidation
import VerificationCore

public struct NativeBuildService: NativeBuildPreparing {
    private let runner: any ToolExecuting
    public init(runner: any ToolExecuting = LocalToolRunner()) { self.runner = runner }
    public func prepare(_ context: BackendContext) async throws -> NativeBuildArtifact {
        let meter = try NativeResourceMeter()
        guard let profile = context.job.native?.profile ?? context.job.fuzz?.profile else { throw InvarError("POLICY_DENIED", "Native build lacks its profile", exitCode: 8) }
        guard let expected = context.job.toolchainIdentity else { throw InvarError("BLOCKED_NATIVE_TOOLCHAIN", "Native toolchain was unavailable at planning", exitCode: 3) }
        let identity = try NativeToolchain.identity(profile)
        guard identity == expected else { throw InvarError("TOOLCHAIN_MISMATCH", "Native build environment differs") }
        let work = context.outputRoot.appendingPathComponent("native")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let binary = try await build(profile, context: context, work: work)
        let bytes = try ArtifactJSON.readBytes(from: binary, maximumBytes: 64 * 1024 * 1024)
        let resources = try meter.measurements()
        return NativeBuildArtifact(planID: context.planID, jobID: context.job.id, binary: binary, binaryDigest: Canonical.digest(bytes), environmentIdentity: identity, resources: resources)
    }
    public func verifyEnvironment(_ context: BackendContext, identity: String) async throws -> [String: Double] {
        let meter = try NativeResourceMeter()
        guard let profile = context.job.native?.profile ?? context.job.fuzz?.profile else { throw InvarError("INVALID_PLAN", "Missing native profile") }
        let current = try NativeToolchain.identity(profile)
        guard current == identity, current == context.job.toolchainIdentity else { throw InvarError("TOOLCHAIN_MISMATCH", "Native environment changed during execution") }
        return try meter.measurements()
    }
    private func build(_ profile: NativeProfile, context: BackendContext, work: URL) async throws -> URL {
        let sourceRoot = work.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: false)
        let sources = profile.modules.flatMap(\.sources) + profile.harness
        for relative in sources {
            guard let entry = context.job.inputs.first(where: { $0.path == relative }) else { throw InvarError("INPUT_UNAVAILABLE", "Native source is absent from the captured input manifest") }
            let bytes = try ArtifactJSON.readBytes(from: context.inputRoot.appendingPathComponent(relative), maximumBytes: 5 * 1024 * 1024)
            guard bytes.count == entry.byteCount, Canonical.digest(bytes) == entry.digest else { throw InvarError("INPUT_MISMATCH", "Captured native source differs") }
            let path = sourceRoot.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: path, options: .atomic)
        }
        let buildProfile = try NativeSandbox.profile(profile, work: work, build: true)
        let runProfile = try NativeSandbox.profile(profile, work: work, build: false)
        try Data(buildProfile.utf8).write(to: work.appendingPathComponent("build.sb")); try Data(runProfile.utf8).write(to: work.appendingPathComponent("run.sb"))
        let probe = try await invoke(profile.compiler, arguments: ["--version"], profile: "build.sb", context: context, work: work, label: "compiler-probe")
        guard probe.exitCode == 0 else { throw InvarError("ISOLATION_UNAVAILABLE", "Compiler could not initialize under the declared sandbox", exitCode: 8) }
        let flags = ["-parse-as-library", "-target", profile.target, "-sdk", profile.sdk, "-tools-directory", profile.toolsDirectory, "-module-cache-path", work.appendingPathComponent("cache").path, "-I", work.path, "-L", work.path]
        var pending = profile.modules, built = Set<String>()
        while !pending.isEmpty {
            guard let index = pending.firstIndex(where: { Set($0.dependencies).isSubset(of: built) }) else { throw InvarError("INVALID_DAG", "Native module dependency cycle", exitCode: 2) }
            let module = pending.remove(at: index)
            let output = work.appendingPathComponent("lib" + module.name + ".dylib")
            let args = flags + ["-emit-library", "-emit-module", "-module-name", module.name, "-emit-module-path", work.appendingPathComponent(module.name + ".swiftmodule").path, "-o", output.path] + module.dependencies.flatMap { ["-l" + $0] } + module.sources.map { sourceRoot.appendingPathComponent($0).path }
            let result = try await invoke(profile.compiler, arguments: args, profile: "build.sb", context: context, work: work, label: "build-" + module.name)
            guard result.exitCode == 0 else { throw InvarError("NATIVE_BUILD_FAILED", "Declared native module failed to compile; private logs retained", exitCode: 7) }
            built.insert(module.name)
        }
        let binary = work.appendingPathComponent("harness")
        let args = flags + ["-module-name", "InvarHarness", "-Xlinker", "-rpath", "-Xlinker", "@executable_path", "-o", binary.path] + built.sorted().map { "-l" + $0 } + profile.harness.map { sourceRoot.appendingPathComponent($0).path }
        let result = try await invoke(profile.compiler, arguments: args, profile: "build.sb", context: context, work: work, label: "build-harness")
        guard result.exitCode == 0 else { throw InvarError("NATIVE_BUILD_FAILED", "Native harness failed to compile; private logs retained", exitCode: 7) }
        return binary
    }
    private func invoke(_ executable: String, arguments: [String], profile: String, context: BackendContext, work: URL, label: String) async throws -> ToolResult {
        let temporary = work.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let environment = ["PATH": profile == "build.sb" ? context.job.native?.profile.toolsDirectory ?? context.job.fuzz!.profile.toolsDirectory : "/usr/bin:/bin", "HOME": work.path, "TMPDIR": temporary.path, "LANG": "C", "LC_ALL": "C", "xcrun_nocache": "1"]
        return try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"), arguments: ["-f", work.appendingPathComponent(profile).path, executable] + arguments,
            directory: work, environment: environment, log: work.appendingPathComponent(label), timeout: context.timeoutSeconds, maximumOutputBytes: context.budget.maximumOutputBytes, maximumWorkspaceBytes: context.budget.maximumWorkspaceBytes)
    }
}
