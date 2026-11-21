import Foundation

public struct VerificationEvidence: Codable, Sendable, Equatable {
    public let inputID: String
    public let executionID: String?
    public let descriptorID: String?
    public let executionKey: String?
    public let jobID: String
    public let execution: String
    public let outcome: String
    public let domain: String
    public let translation: String
    public let scope: String
    public let adequacy: String
    public let detail: String
    public let assumptions: [String]
    public let witnessFactIDs: [String]
    public let artifacts: [EvidenceArtifactReference]
    public let resources: [String:Double]
    public let diagnosticCode: String?
    public let startedAt: String
    public let finishedAt: String
    public let reproductionKey: String?
    public var id: String {
        let artifactParts = artifacts.sorted { $0.id < $1.id }.flatMap { [$0.id,$0.sha256,String($0.byteCount),$0.mediaType,$0.profile] }
        let measurementParts = resources.keys.sorted().flatMap { [$0,String(resources[$0]!.bitPattern)] }
        return Canonical.parts("invar.evidence/2",[inputID,executionID.map { "present:" + $0 } ?? "absent",descriptorID.map { "present:" + $0 } ?? "absent",executionKey.map { "present:" + $0 } ?? "absent",jobID,execution,outcome,domain,translation,scope,adequacy,detail,diagnosticCode.map { "present:" + $0 } ?? "absent",startedAt,finishedAt,reproductionKey.map { "present:" + $0 } ?? "absent"] + ["assumptions",String(assumptions.count)] + assumptions.sorted() + ["witnessFacts",String(witnessFactIDs.count)] + witnessFactIDs.sorted() + ["artifacts",String(artifacts.count)] + artifactParts + ["measurements",String(resources.count)] + measurementParts)
    }
    public init(inputID: String, executionID: String? = nil, descriptorID: String? = nil, executionKey: String? = nil, jobID: String, execution: String, outcome: String, domain: String, translation: String, scope: String, adequacy: String = "unknown", detail: String, assumptions: [String] = [], witnessFactIDs: [String] = [], artifacts: [EvidenceArtifactReference] = [], resources: [String:Double] = [:], diagnosticCode: String? = nil, startedAt: String, finishedAt: String, reproductionKey: String? = nil) {
        self.inputID = inputID
        self.executionID = executionID
        self.descriptorID = descriptorID; self.executionKey = executionKey
        self.jobID = jobID
        self.execution = execution
        self.outcome = outcome
        self.domain = domain
        self.translation = translation
        self.scope = scope
        self.adequacy = adequacy
        self.detail = detail
        self.assumptions = Array(Set(assumptions)).sorted()
        self.witnessFactIDs = Array(Set(witnessFactIDs)).sorted()
        self.artifacts = artifacts.sorted { $0.id < $1.id }
        self.resources = resources
        self.diagnosticCode = diagnosticCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.reproductionKey = reproductionKey
    }
    public func measuring(_ values: [String:Double]) -> Self {
        Self(inputID: inputID, executionID: executionID, descriptorID: descriptorID, executionKey: executionKey, jobID: jobID, execution: execution, outcome: outcome, domain: domain, translation: translation, scope: scope, adequacy: adequacy, detail: detail, assumptions: assumptions, witnessFactIDs: witnessFactIDs, artifacts: artifacts, resources: values, diagnosticCode: diagnosticCode, startedAt: startedAt, finishedAt: finishedAt, reproductionKey: reproductionKey)
    }
    public func binding(executionID: String,descriptorID: String,executionKey: String?) -> Self {
        Self(inputID: inputID,executionID: executionID,descriptorID: descriptorID,executionKey: executionKey,jobID: jobID,execution: execution,outcome: outcome,domain: domain,translation: translation,scope: scope,adequacy: adequacy,detail: detail,assumptions: assumptions,witnessFactIDs: witnessFactIDs,artifacts: artifacts,resources: resources,diagnosticCode: diagnosticCode,startedAt: startedAt,finishedAt: finishedAt,reproductionKey: reproductionKey)
    }
    private enum Key: String, CodingKey { case id, inputID, executionID, descriptorID, executionKey, jobID, execution, outcome, domain, translation, scope, adequacy, detail, assumptions, witnessFactIDs, artifacts, resources, diagnosticCode, startedAt, finishedAt, reproductionKey }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let inputID = try container.decode(String.self,forKey: .inputID)
        let executionID = try container.decodeIfPresent(String.self,forKey: .executionID)
        let descriptorID = try container.decodeIfPresent(String.self,forKey: .descriptorID)
        let executionKey = try container.decodeIfPresent(String.self,forKey: .executionKey)
        let jobID = try container.decode(String.self,forKey: .jobID)
        let execution = try container.decode(String.self,forKey: .execution)
        let outcome = try container.decode(String.self,forKey: .outcome)
        let domain = try container.decode(String.self,forKey: .domain)
        let translation = try container.decode(String.self,forKey: .translation)
        let scope = try container.decode(String.self,forKey: .scope)
        let adequacy = try container.decode(String.self,forKey: .adequacy)
        let detail = try container.decode(String.self,forKey: .detail)
        let assumptions = try container.decode([String].self,forKey: .assumptions)
        let witnessFactIDs = try container.decode([String].self,forKey: .witnessFactIDs)
        let artifacts = try container.decode([EvidenceArtifactReference].self,forKey: .artifacts)
        let resources = try container.decode([String:Double].self,forKey: .resources)
        let diagnosticCode = try container.decodeIfPresent(String.self,forKey: .diagnosticCode)
        let startedAt = try container.decode(String.self,forKey: .startedAt)
        let finishedAt = try container.decode(String.self,forKey: .finishedAt)
        let reproductionKey = try container.decodeIfPresent(String.self,forKey: .reproductionKey)
        self.init(inputID: inputID, executionID: executionID, descriptorID: descriptorID, executionKey: executionKey, jobID: jobID, execution: execution, outcome: outcome, domain: domain, translation: translation, scope: scope, adequacy: adequacy, detail: detail, assumptions: assumptions, witnessFactIDs: witnessFactIDs, artifacts: artifacts, resources: resources, diagnosticCode: diagnosticCode, startedAt: startedAt, finishedAt: finishedAt, reproductionKey: reproductionKey)
        let recorded = try container.decode(String.self,forKey: .id)
        guard recorded == id else { throw InvarError("STORE_INTEGRITY","Evidence identity differs from immutable content") }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id,forKey: .id)
        try container.encode(inputID,forKey: .inputID)
        try container.encodeIfPresent(executionID,forKey: .executionID)
        try container.encodeIfPresent(descriptorID,forKey: .descriptorID)
        try container.encodeIfPresent(executionKey,forKey: .executionKey)
        try container.encode(jobID,forKey: .jobID)
        try container.encode(execution,forKey: .execution)
        try container.encode(outcome,forKey: .outcome)
        try container.encode(domain,forKey: .domain)
        try container.encode(translation,forKey: .translation)
        try container.encode(scope,forKey: .scope)
        try container.encode(adequacy,forKey: .adequacy)
        try container.encode(detail,forKey: .detail)
        try container.encode(assumptions,forKey: .assumptions)
        try container.encode(witnessFactIDs,forKey: .witnessFactIDs)
        try container.encode(artifacts,forKey: .artifacts)
        try container.encode(resources,forKey: .resources)
        try container.encodeIfPresent(diagnosticCode,forKey: .diagnosticCode)
        try container.encode(startedAt,forKey: .startedAt)
        try container.encode(finishedAt,forKey: .finishedAt)
        try container.encodeIfPresent(reproductionKey,forKey: .reproductionKey)
    }
}
