import ArchitectureCore
import Foundation
import VerificationCore

public actor ExplorerSourceEvents: SourceEventReading {
    private let request: @Sendable (JSONValue) async throws -> (sessionID: String,value: JSONValue)
    private var sessionID: String?
    private var epoch: String?
    private var snapshotID: String?
    private var sequence: Int?
    private var extensionSequence: JSONValue = .null
    private var sessionRevision: JSONValue = .null
    private var wasReady = false
    private var uncertain = true
    public init(connection: any ExplorerConnecting) {
        request = { parameters in
            let provider = try await connection.provider()
            let value = try await provider.client.call("events.poll",parameters: parameters)
            return (provider.registration.sessionID,value)
        }
    }
    init(request: @escaping @Sendable (JSONValue) async throws -> (sessionID: String,value: JSONValue)) { self.request = request }
    public func poll() async throws -> SourceEvent {
        let parameters: JSONValue = .object(["snapshotID":snapshotID.map(JSONValue.string) ?? .null,"streamEpoch":epoch.map(JSONValue.string) ?? .null,"extensionSequence":extensionSequence,"sessionRevision":sessionRevision])
        do {
            let response = try await request(parameters), value = response.value
            let bytes = try CanonicalJSON.encode(value)
            guard bytes.count <= 16384, !response.sessionID.isEmpty, response.sessionID.utf8.count <= 128,
                let nextEpoch = value["streamEpoch"].string, !nextEpoch.isEmpty, nextEpoch.utf8.count <= 128,
                let type = value["type"].string, ["viewInvalidated","unchanged","analysisStatusChanged"].contains(type) else { throw InvarError("UPSTREAM_PROTOCOL","Malformed source event") }
            let nextSnapshot = value["snapshotID"].string, nextSequence = value["sequence"].int
            let ready = type != "analysisStatusChanged"
            guard nextSnapshot.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? (value["snapshotID"] == .null),
                !ready || nextSnapshot != nil && nextSequence != nil,
                nextSequence.map({ $0 >= 0 }) ?? !ready else { throw InvarError("UPSTREAM_PROTOCOL","Source event lacks a coherent published snapshot/generation") }
            var lost = uncertain || response.sessionID != sessionID || nextEpoch != epoch
            if nextEpoch == epoch, let old = sequence, let next = nextSequence {
                if next < old || next > old && next-old > 1 { lost = true }
            }
            let invalidated = lost || !ready || !wasReady || nextSnapshot != snapshotID || type == "viewInvalidated"
            let reason = !ready ? "Source analysis is pending or no snapshot is available" : lost ? "Source event continuity requires resync" : invalidated ? "Source snapshot changed" : nil
            sessionID = response.sessionID; epoch = nextEpoch; snapshotID = nextSnapshot
            if let nextSequence { sequence = nextSequence }
            extensionSequence = value["extensionSequence"]; sessionRevision = value["sessionRevision"]
            wasReady = ready; uncertain = false
            return SourceEvent(epoch: nextEpoch,snapshotID: nextSnapshot,sequence: nextSequence,ready: ready,invalidated: invalidated,continuityLost: lost,reason: reason)
        } catch { uncertain = true; throw error }
    }
}
