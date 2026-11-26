import Foundation
import FormalValidation
import Testing
@testable import VerificationBackends

@Suite(.timeLimit(.minutes(1)))
struct ProjectSandboxTests {
    @Test func configuredJavaCanReadItsRuntimeConfiguration() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("invar-java-sandbox-" + UUID().uuidString)
        let attempt = root.appendingPathComponent("attempt")
        let javaHome = root.appendingPathComponent("jdk")
        let java = javaHome.appendingPathComponent("bin/java")
        let security = javaHome.appendingPathComponent("conf/security/java.security")
        let privateFile = root.appendingPathComponent("private.txt")
        for directory in [attempt, java.deletingLastPathComponent(), security.deletingLastPathComponent()] {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer {
            do { try files.removeItem(at: root) }
            catch { Issue.record(error) }
        }
        try Data().write(to: java)
        try Data("java-runtime-configuration".utf8).write(to: security)
        try Data("outside-runtime".utf8).write(to: privateFile)
        let profile = try ProjectSandbox.install(at: attempt, tools: [java.path])
        let runner = LocalToolRunner()
        let permitted = try await runner.run(
            executable: ProjectSandbox.executable,
            arguments: ["-f", profile.path, "/bin/cat", security.path],
            directory: attempt, environment: [:], log: root.appendingPathComponent("permitted"),
            timeout: 5, maximumOutputBytes: 8192, maximumWorkspaceBytes: 1048576)
        #expect(permitted.exitCode == 0)
        #expect(permitted.standardOutput == "java-runtime-configuration")
        let blocked = try await runner.run(
            executable: ProjectSandbox.executable,
            arguments: ["-f", profile.path, "/bin/cat", privateFile.path],
            directory: attempt, environment: [:], log: root.appendingPathComponent("blocked"),
            timeout: 5, maximumOutputBytes: 8192, maximumWorkspaceBytes: 1048576)
        #expect(blocked.exitCode != 0)
        #expect(blocked.standardOutput.isEmpty)
    }
}
