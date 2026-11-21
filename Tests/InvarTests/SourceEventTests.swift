import ArchitectureCore
import Foundation
import Testing
import VerificationCore
@testable import VerificationExplorer

@Suite(.timeLimit(.minutes(1))) struct SourceEventTests {
    actor Feed {
        var session = "session", value: JSONValue = .null, failed = false
        var lastParameters: JSONValue = .null
        func set(_ value: JSONValue,session: String = "session",failed: Bool = false) { self.value = value; self.session = session; self.failed = failed }
        func poll(_ parameters: JSONValue) throws -> (sessionID: String,value: JSONValue) {
            lastParameters = parameters
            if failed { throw InvarError("SOURCE_OFFLINE","Injected transport failure") }
            return (session,value)
        }
    }
    func value(type: String = "unchanged",epoch: String = "epoch",snapshot: String = "snapshot",sequence: Int = 1,extensions: Int = 1) -> JSONValue {
        .object(["type":.string(type),"streamEpoch":.string(epoch),"snapshotID":.string(snapshot),"sequence":.number(Double(sequence)),"extensionSequence":.number(Double(extensions)),"sessionRevision":.string("sessions"),"originProviderID":.string("invar"),"category":.string("extensions"),"extensionChanged":.bool(true)])
    }
    @Test func ownPublicationOnlyAdvancesExtensionCursorWhileSourceGapsAndPendingAnalysisInvalidate() async throws {
        let feed = Feed(), reader = ExplorerSourceEvents { try await feed.poll($0) }
        await feed.set(value())
        let first = try await reader.poll()
        #expect(first.ready && first.invalidated && first.continuityLost)
        await feed.set(value(extensions: 2))
        let ownPublication = try await reader.poll()
        #expect(ownPublication.ready && !ownPublication.invalidated && !ownPublication.continuityLost)
        #expect(await feed.lastParameters["extensionSequence"] == .number(1))
        await feed.set(value(type: "analysisStatusChanged",extensions: 3))
        let pending = try await reader.poll()
        #expect(!pending.ready && pending.invalidated)
        await feed.set(value(type: "viewInvalidated",snapshot: "next",sequence: 3,extensions: 4))
        let gap = try await reader.poll()
        #expect(gap.ready && gap.invalidated && gap.continuityLost)
        await feed.set(value(snapshot: "next",sequence: 3,extensions: 5),session: "replacement-session")
        #expect(try await reader.poll().continuityLost)
    }
    @Test func failedOrMalformedObservationCannotResumeAsUnchangedAndEpochResetRequiresResync() async throws {
        let feed = Feed(), reader = ExplorerSourceEvents { try await feed.poll($0) }
        await feed.set(value()); _ = try await reader.poll()
        await feed.set(value(),failed: true)
        await #expect(throws: InvarError.self) { try await reader.poll() }
        await feed.set(value())
        #expect(try await reader.poll().continuityLost)
        await feed.set(value(type: "unknown-future-event"))
        await #expect(throws: InvarError.self) { try await reader.poll() }
        await feed.set(value(epoch: "restarted",sequence: 0))
        #expect(try await reader.poll().continuityLost)
    }
}
