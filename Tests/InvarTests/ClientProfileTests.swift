import Foundation
import Testing
import VerificationClient
import VerificationCore

@Suite(.timeLimit(.minutes(1))) struct ClientProfileTests {
    @Test func concurrentClientsResumeOneOriginalPrincipalAndChangedScopeFailsBeforeConnecting() async throws {
        let environment = try await DaemonProtocolTests().environment()
        defer { do { try await environment.shutdown() } catch { Issue.record(error) } }
        let directory = environment.root.appendingPathComponent("profiles"), workspace = environment.root.appendingPathComponent("workspace")
        let profile = try LocalClientProfile(directory: directory,profile: "agent",workspace: workspace,workspaceID: environment.endpoint.workspaceID,daemonState: environment.ownership.paths.stateDirectory)
        let clients = try await withThrowingTaskGroup(of: LocalVerificationClient.self) { group in
            for _ in 0..<4 { group.addTask { try await profile.connect(endpoint: environment.endpoint,label: "same-profile",capabilities: [.read,.verification]) } }
            var values: [LocalVerificationClient] = []
            for try await value in group { values.append(value) }
            return values
        }
        defer { for client in clients { await client.shutdown() } }
        var principals = Set<String>()
        for client in clients { let session = try await client.session(); principals.insert(session.principal) }
        #expect(principals.count == 1)
        await #expect(throws: InvarError.self) { try await profile.connect(endpoint: environment.endpoint,label: "widened",capabilities: [.read,.verification,.planning]) }
        let records = try FileManager.default.contentsOfDirectory(at: directory,includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        #expect(records.count == 1)
        let path = try #require(records.first)
        try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath: path.path)
        await #expect(throws: InvarError.self) { try await profile.connect(endpoint: environment.endpoint,label: "unsafe",capabilities: [.read,.verification]) }
    }
    @Test func profileCannotWriteCredentialsIntoTheWorkspaceOrDaemonStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-client-profile-" + UUID().uuidString)
        let workspace = root.appendingPathComponent("workspace"), state = root.appendingPathComponent("state")
        for directory in [workspace,workspace.appendingPathComponent("profiles"),state.appendingPathComponent("profiles")] {
            #expect(throws: InvarError.self) { try LocalClientProfile(directory: directory,profile: "agent",workspace: workspace,workspaceID: "workspace",daemonState: state) }
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
