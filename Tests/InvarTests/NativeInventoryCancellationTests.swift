import Foundation
import Testing
import VerificationBackends
import VerificationCore

@Suite(.timeLimit(.minutes(1)))
struct NativeInventoryCancellationTests {
    actor Start { var entered = false; func enter() { entered = true } }
    @Test func temporaryDirectoryAliasesRetainExactRelativeInventoryAndDetectChangedBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-native-inventory-" + UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let tools = root.appendingPathComponent("Fixture.xctoolchain/usr/bin"), sdk = root.appendingPathComponent("SDK")
        try FileManager.default.createDirectory(at: tools,withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sdk,withIntermediateDirectories: true)
        for name in ["swiftc","ld"] {
            let path = tools.appendingPathComponent(name)
            try Data("fixture executable identity\n".utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700],ofItemAtPath: path.path)
        }
        let profile = NativeProfile(compiler: tools.appendingPathComponent("swiftc").path,sdk: sdk.path,toolsDirectory: tools.path,modules: [],harness: ["Harness.swift"])
        let first = try NativeToolchain.identity(profile)
        let repeated = try NativeToolchain.identity(profile)
        #expect(first == repeated)
        try Data("changed fixture executable identity\n".utf8).write(to: tools.appendingPathComponent("ld"))
        let changed = try NativeToolchain.identity(profile)
        #expect(first != changed)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INVAR_NATIVE_CANCELLATION_PROBE"] == "1")) func cancellationDuringOneLargeRegularArtifactStopsBeforeItsWholeHashCompletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-native-cancellation-" + UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let toolchain = root.appendingPathComponent("Fixture.xctoolchain"), tools = toolchain.appendingPathComponent("usr/bin"), sdk = root.appendingPathComponent("SDK")
        try FileManager.default.createDirectory(at: tools,withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sdk,withIntermediateDirectories: true)
        for name in ["swiftc","ld"] {
            let path = tools.appendingPathComponent(name)
            // Identity inventories these bytes; this fixture never executes a tool.
            try Data("fixture executable identity\n".utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700],ofItemAtPath: path.path)
        }
        let path = toolchain.appendingPathComponent("00-large-artifact")
        try Data().write(to: path)
        let file = try FileHandle(forWritingTo: path)
        do {
            // A sparse file exercises a large read without allocating its logical disk size.
            try file.truncate(atOffset: 16_000_000_000)
            try file.close()
        } catch { do { try file.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Sparse fixture setup failed (\(error)); close failed (\(cleanup))") }; throw error }
        let profile = NativeProfile(compiler: tools.appendingPathComponent("swiftc").path,sdk: sdk.path,toolsDirectory: tools.path,modules: [],harness: ["Harness.swift"])
        let start = Start()
        let task = Task.detached {
            await start.enter()
            return try NativeToolchain.identity(profile)
        }
        while !(await start.entered) { try await Task.sleep(for: .milliseconds(2)) }
        try await Task.sleep(for: .milliseconds(100))
        let cancelledAt = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled native inventory returned success") }
        catch is CancellationError {}
        catch { Issue.record(error) }
        let delay = cancelledAt.duration(to: .now)
        #expect(delay < .seconds(1),"Cancellation must be observed inside a large file, not after hashing the complete artifact")
    }
}
