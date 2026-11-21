import Foundation
import Testing
import VerificationCore
@testable import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct StoreIntegrityTests {
    @Test func retainedRunWithForgedAssessmentIsRejectedThroughActualReadPath() async throws {
        let fixture = try await PublicationTests().fixture()
        defer { do { try await PublicationTests().cleanup(fixture) } catch { Issue.record(error) } }
        let demand = try await PublicationTests().execute(fixture,key: "corruption")
        let id = try #require(demand.resultID), original = try await fixture.store.loadRun(id)
        let forged = VerificationRun(id: original.id,planID: original.planID,attempts: original.attempts,associations: original.associations,accepted: !original.accepted,diagnostics: original.diagnostics)
        let bytes = try Canonical.encode(forged)
        try await fixture.store.replaceRunBytesForIntegrityTest(id,bytes: bytes)
        do { _ = try await fixture.store.loadRun(id); Issue.record("Corrupted aggregate was accepted") }
        catch let error as InvarError { #expect(error.code == "INVALID_RESULT") }
    }
    @Test func unknownStoreSchemaRemainsUnchangedAfterRefusedOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root)
        try await store.setSchemaForIntegrityTest(999)
        try await store.shutdown()
        let path = root.appendingPathComponent("verification.sqlite"), original = try Data(contentsOf: path)
        do { _ = try SQLiteVerificationStore(root: root); Issue.record("Unknown layout was accepted") }
        catch let error as InvarError { #expect(error.code == "UNSUPPORTED_STORE_SCHEMA") }
        #expect(try Data(contentsOf: path) == original)
        try FileManager.default.removeItem(at: root)
    }
    @Test func databaseSymlinkIsRefusedBeforeTouchingItsTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true,attributes: [.posixPermissions:0o700])
        let bytes = Data("untouched".utf8)
        try bytes.write(to: outside)
        defer { do { try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: outside) } catch { Issue.record(error) } }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("verification.sqlite"),withDestinationURL: outside)
        do { _ = try SQLiteVerificationStore(root: root); Issue.record("Database symlink was accepted") }
        catch let error as InvarError { #expect(error.code == "UNSAFE_STORE") }
        #expect(try Data(contentsOf: outside) == bytes)
    }
}

extension SQLiteVerificationStore {
    // Deliberate raw corruption bypasses immutable insertion to exercise the real reader's audit.
    fileprivate func replaceRunBytesForIntegrityTest(_ id: String,bytes: Data) throws {
        let payload = bytes.map { String(format: "%02x",$0) }.joined()
        let key = Data(id.utf8).map { String(format: "%02x",$0) }.joined()
        try database.execute("UPDATE records SET payload=x'" + payload + "' WHERE namespace='run' AND id=CAST(x'" + key + "' AS TEXT)")
    }
    fileprivate func setSchemaForIntegrityTest(_ version: Int) throws {
        try database.execute("PRAGMA user_version=" + String(version))
    }
}
