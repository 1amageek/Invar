import VerificationCore

public actor DaemonState: DaemonStateReading {
    public enum Phase: String, Sendable {
        case starting, recovering, ready, sourceOffline, approvalRequired, recoveryBlocked, draining, stopped
    }
    private let workspaceID: String
    private let epoch: String
    private let engineIdentity: String
    private var phase: Phase = .starting
    private var diagnostics: [String] = []
    public init(workspaceID: String,epoch: String,engineIdentity: String) {
        self.workspaceID = workspaceID; self.epoch = epoch; self.engineIdentity = engineIdentity
    }
    public func transition(to next: Phase,diagnostics: [String] = []) throws {
        let allowed: Set<Phase>
        switch phase {
        case .starting: allowed = [.recovering,.recoveryBlocked,.draining]
        case .recovering: allowed = [.ready,.sourceOffline,.approvalRequired,.recoveryBlocked,.draining]
        case .ready,.sourceOffline,.approvalRequired: allowed = [.ready,.sourceOffline,.approvalRequired,.recoveryBlocked,.draining]
        case .draining: allowed = [.stopped,.recoveryBlocked]
        case .recoveryBlocked: allowed = [.draining]
        case .stopped: allowed = []
        }
        guard next == phase || allowed.contains(next), diagnostics.count <= 32, diagnostics.allSatisfy({ $0.utf8.count <= 4096 }) else { throw InvarError("INVALID_TRANSITION","Invalid daemon phase/diagnostics") }
        phase = next; self.diagnostics = diagnostics
    }
    public func status(activeOperations: Int,watchCount: Int) -> DaemonStatus {
        DaemonStatus(workspaceID: workspaceID,epoch: epoch,engineIdentity: engineIdentity,state: phase.rawValue,activeOperations: activeOperations,watchCount: watchCount,diagnostics: diagnostics)
    }
}
