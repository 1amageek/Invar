import Foundation

public struct WorkspacePolicy: Codable, Sendable, Equatable {
    public let workspaceID: String
    public let engineIdentity: String
    public let revision: Int
    public let peers: [PeerGrant]
    public let approvals: [ContractApproval]
    public let sessionSeconds: Double
    public let principalSeconds: Double
    public let maximumSessions: Int
    public let maximumConnections: Int
    public let maximumEnvelopeSeconds: Double
    public init(workspaceID: String,engineIdentity: String,revision: Int,peers: [PeerGrant],approvals: [ContractApproval],sessionSeconds: Double,principalSeconds: Double,maximumSessions: Int,maximumConnections: Int,maximumEnvelopeSeconds: Double) {
        self.workspaceID = workspaceID; self.engineIdentity = engineIdentity; self.revision = revision
        self.peers = peers.sorted { $0.binaryDigest < $1.binaryDigest }; self.approvals = approvals.sorted { $0.configurationDigest < $1.configurationDigest }
        self.sessionSeconds = sessionSeconds; self.principalSeconds = principalSeconds; self.maximumSessions = maximumSessions
        self.maximumConnections = maximumConnections; self.maximumEnvelopeSeconds = maximumEnvelopeSeconds
    }
    public func validate(retentionSeconds: Double) throws {
        func digest(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        guard !workspaceID.isEmpty, digest(engineIdentity), revision > 0, peers.count <= 64, approvals.count <= 500,
            Set(peers.map(\.binaryDigest)).count == peers.count, peers.allSatisfy({ digest($0.binaryDigest) && Set($0.capabilities).count == $0.capabilities.count }),
            Set(approvals.map(\.configurationDigest)).count == approvals.count,
            sessionSeconds.isFinite, principalSeconds.isFinite, sessionSeconds > 0, sessionSeconds <= principalSeconds, principalSeconds <= retentionSeconds,
            (1...1024).contains(maximumSessions), (2...64).contains(maximumConnections), maximumEnvelopeSeconds.isFinite, (1...3600).contains(maximumEnvelopeSeconds) else { throw InvarError("INVALID_POLICY","Invalid workspace authority policy",exitCode: 2) }
        for approval in approvals {
            guard digest(approval.configurationDigest), approval.entries.count <= 512, Set(approval.entries.map(\.path)).count == approval.entries.count else { throw InvarError("INVALID_POLICY","Invalid contract approval") }
            for entry in approval.entries {
                _ = try Canonical.relative(entry.path)
                guard digest(entry.digest), (0...5 * 1024 * 1024).contains(entry.byteCount) else { throw InvarError("INVALID_POLICY","Invalid approved contract bytes") }
            }
        }
    }
}
