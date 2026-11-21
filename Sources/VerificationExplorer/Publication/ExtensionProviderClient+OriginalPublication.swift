import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import VerificationCore

extension ExtensionProviderClient: OriginalPublicationChecking {
    public func requireOriginalRun(_ run: ExtensionRun) async throws {
        guard run.providerID == registration.providerID else { throw InvarError("INVALID_PUBLICATION","Original run belongs to another provider") }
        var cursor: String?, seen = Set<String>(), records = 0
        for _ in 0..<833 {
            let parameters: JSONValue = cursor.map { .object(["cursor":.string($0)]) } ?? .object([:])
            let page = try await client.call("extensions.view",parameters: parameters)
            let count = ["registrations","actions","publications","attempts"].reduce(0) { $0 + page[$1].array.count }
            records += count
            guard records <= 832, try CanonicalJSON.encode(page).count <= 4 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT","Original run inventory exceeds its bounded profile") }
            for attempt in page["attempts"].array where attempt["runID"].string == run.id {
                guard attempt["slot"].string == run.slot, attempt["generation"] == .number(Double(run.generation)) else { throw InvarError("IDEMPOTENCY_CONFLICT","Original publication reservation changed") }
                return
            }
            guard page["nextCursor"] != .null else { throw InvarError("ORIGINAL_RUN_LOST","Original Explorer run is absent; a replacement generation cannot be created") }
            guard let next = page["nextCursor"].string, count > 0, !next.isEmpty, next.utf8.count <= 256, seen.insert(next).inserted else { throw InvarError("PROTOCOL_MISMATCH","Invalid original run inventory cursor") }
            cursor = next
        }
        throw InvarError("RESOURCE_LIMIT","Original run inventory page bound exceeded")
    }
}
