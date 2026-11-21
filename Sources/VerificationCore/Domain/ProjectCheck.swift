import Foundation

/// Host-reviewed whole-project workflow and its complete acceptance report.
public struct ProjectCheck: Codable, Sendable, Equatable {
    public let id: String
    public let subjectID: String
    public let command: [String]
    public let toolDigests: [String:String]
    public let reportBuilder: String
    public let report: String
    public let contracts: [String]
    public let budget: RunBudget
    public let approved: Bool
    public let required: Bool
    public init(id: String,subjectID: String,command: [String],toolDigests: [String:String],reportBuilder: String,report: String,contracts: [String],budget: RunBudget,approved: Bool,required: Bool = true) {
        self.id = id; self.subjectID = subjectID; self.command = command; self.toolDigests = toolDigests
        self.reportBuilder = reportBuilder; self.report = report; self.contracts = contracts; self.budget = budget
        self.approved = approved; self.required = required
    }
    public func includes(_ path: String) -> Bool {
        guard let separator = report.lastIndex(of: "/") else { return false }
        let directory = String(report.prefix(through: separator))
        return path != report && !path.hasPrefix(directory + "runs/") && path != directory + "manifest.json"
    }
    public func validate() throws {
        try PlanValidation.identifier(id); try PlanValidation.budget(budget)
        _ = try Canonical.relative(report)
        guard !subjectID.isEmpty, subjectID.utf8.count <= 256, command.count >= 2, command.count <= 64,
            command.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 && !$0.contains("\0") }),
            command[0].hasPrefix("/"), command[1].first != "-", !command[1].hasPrefix("/"),
            report.contains("/"), report.hasSuffix("/Report.json"),
            !contracts.isEmpty, contracts.count <= 512, Set(contracts).count == contracts.count, contracts.contains(command[1]),
            toolDigests.count <= 32, toolDigests[command[0]] != nil, toolDigests[reportBuilder] != nil,
            toolDigests.allSatisfy({ $0.key.hasPrefix("/") && $0.value.utf8.count == 64 && $0.value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) })
        else { throw InvarError("INVALID_CONFIGURATION","Project verification requires a subject, reviewed argv, exact tool digests, contract paths and bounded report") }
        for path in contracts { _ = try Canonical.relative(path); guard includes(path) else { throw InvarError("INVALID_CONFIGURATION","Project contract cannot be a prior generated report") } }
        _ = try Canonical.relative(command[1])
    }
}
