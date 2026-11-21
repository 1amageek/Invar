import Darwin
import Foundation
import Testing
import VerificationCore
import VerificationDaemon

@Suite(.timeLimit(.minutes(1))) struct DaemonOwnershipTests {
    @Test func workspaceLockIsIndependentOfStateRootAndReleasesExactlyOnce() async throws {
        let workspaceID = Canonical.digest(Data(UUID().uuidString.utf8))
        let paths = DaemonEndpointPaths(workspaceID: workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: URL(fileURLWithPath: "/tmp/first-state"))
        defer { do { try FileManager.default.removeItem(at: paths.runtimeDirectory) } catch { Issue.record(error) } }
        let first = try DaemonOwnership(paths: paths)
        let other = DaemonEndpointPaths(workspaceID: workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: URL(fileURLWithPath: "/tmp/second-state"))
        #expect(throws: InvarError.self) { try DaemonOwnership(paths: other) }
        try await first.release(); try await first.release()
        let replacement = try DaemonOwnership(paths: other)
        try await replacement.release()
    }
    @Test func aliasesAndMissingChildrenCannotPutStateInsideWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let workspace = root.appendingPathComponent("workspace"), alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: workspace,withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: alias,withDestinationURL: workspace)
        #expect(throws: InvarError.self) { try DaemonPathValidation.stateRoot(alias.appendingPathComponent("missing/state"),outside: workspace) }
        let outside = try DaemonPathValidation.stateRoot(root.appendingPathComponent("private-state"),outside: workspace)
        #expect(outside.lastPathComponent == "private-state")
    }
}
