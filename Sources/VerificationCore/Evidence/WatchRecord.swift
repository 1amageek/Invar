import Foundation

public struct WatchRecord: Codable, Sendable, Equatable {
    public let id: String
    public let envelopeID: String
    public let workspaceID: String
    public let principal: String
    public let configurationPath: String
    public let budget: RunBudget
    public let expiresAt: Double
    public let revision: Int
    public let state: String
    public let stopTarget: String?
    public let cycle: WatchCycle
    public let lastPlanID: String?
    public let lastRunID: String?
    public let lastView: ViewReference?
    public let failure: InvarError?
    public init(id: String,envelopeID: String,workspaceID: String,principal: String,configurationPath: String,budget: RunBudget,expiresAt: Double,revision: Int = 1,state: String = "registering",stopTarget: String? = nil,cycle: WatchCycle = WatchCycle(),lastPlanID: String? = nil,lastRunID: String? = nil,lastView: ViewReference? = nil,failure: InvarError? = nil) {
        self.id = id; self.envelopeID = envelopeID; self.workspaceID = workspaceID; self.principal = principal
        self.configurationPath = configurationPath; self.budget = budget; self.expiresAt = expiresAt
        self.revision = revision; self.state = state; self.stopTarget = stopTarget; self.cycle = cycle; self.lastPlanID = lastPlanID; self.lastRunID = lastRunID; self.lastView = lastView; self.failure = failure
    }
    public func revising(state: String,stopTarget: String? = nil,cycle: WatchCycle? = nil,lastPlanID: String? = nil,lastRunID: String? = nil,lastView: ViewReference? = nil,failure: InvarError? = nil) -> Self {
        Self(id: id,envelopeID: envelopeID,workspaceID: workspaceID,principal: principal,configurationPath: configurationPath,budget: budget,expiresAt: expiresAt,revision: revision+1,state: state,stopTarget: stopTarget ?? self.stopTarget,cycle: cycle ?? self.cycle,lastPlanID: lastPlanID ?? self.lastPlanID,lastRunID: lastRunID ?? self.lastRunID,lastView: lastView ?? self.lastView,failure: failure)
    }
}
