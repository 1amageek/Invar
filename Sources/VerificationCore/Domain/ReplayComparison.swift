import Foundation

public struct ReplayComparison: Codable, Sendable, Equatable {
    public let originalRunID: String
    public let replayRunID: String
    public let jobs: [String: String]
    public init(original: VerificationRun, replay: VerificationRun) throws {
        guard original.planID == replay.planID, original.id != replay.id else { throw InvarError("INVALID_REPLAY", "Replay must be a distinct run of the same sealed plan", exitCode: 2) }
        originalRunID = original.id; replayRunID = replay.id
        var values: [String: String] = [:]
        for old in original.attempts where old.outcome == "violatedWithinScope" {
            guard let current = replay.attempts.first(where: { $0.jobID == old.jobID }), current.execution == "completed", !["unknown", "notEvaluated"].contains(current.outcome) else { values[old.jobID] = "inconclusive"; continue }
            if old.domain == "nativeExecution", old.reproductionKey == nil { values[old.jobID] = "inconclusive"; continue }
            let same = current.reproductionKey == old.reproductionKey && current.witnessFactIDs.sorted() == old.witnessFactIDs.sorted() && current.outcome == old.outcome && current.domain == old.domain && current.translation == old.translation && current.scope == old.scope && current.diagnosticCode == old.diagnosticCode
            values[old.jobID] = same ? "reproduced" : "unreproduced"
        }
        jobs = values
    }
}
