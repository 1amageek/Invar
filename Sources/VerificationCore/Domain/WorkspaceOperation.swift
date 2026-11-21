import Foundation

public enum WorkspaceOperation: Codable, Sendable, Equatable {
    case openChange(claim: ChangeClaim?,configurationPath: String? = nil)
    case sealChange(changeID: String)
    case preparePlan(configurationPath: String,changeRevisionID: String?,budget: RunBudget)
    case verify(planID: String,changeRevisionID: String?,replayOfRunID: String?, node: VerificationNode? = nil)
    case reconcile(planID: String,runID: String)
    case watch(configurationPath: String,budget: RunBudget)
    case cancel(demandID: String)
    case stopWatch(watchID: String)

    public var verificationNode: VerificationNode? {
        if case .verify(_, _, _, let node) = self { return node }
        return nil
    }

    public var requiredCapability: WorkspaceCapability {
        switch self {
        case .openChange,.sealChange: .changes
        case .preparePlan: .planning
        case .verify,.reconcile,.cancel: .verification
        case .watch,.stopWatch: .watching
        }
    }
    public var name: String {
        switch self {
        case .openChange: "change.open"
        case .sealChange: "change.seal"
        case .preparePlan: "plan.prepare"
        case .verify: "verification.run"
        case .reconcile: "verification.reconcile"
        case .watch: "watch.create"
        case .cancel: "demand.cancel"
        case .stopWatch: "watch.stop"
        }
    }
}
