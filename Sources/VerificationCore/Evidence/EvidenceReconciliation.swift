public enum EvidenceReconciliation {
    public static func associations(run: VerificationRun,original: SchedulingPlan,target: SchedulingPlan) throws -> [EvidenceAssociation] {
        guard run.planID == original.id, original.input.workspaceID == target.input.workspaceID,
            original.capturedScopeDigest == target.capturedScopeDigest,
            !run.attempts.isEmpty, run.attempts.allSatisfy({ $0.execution == "completed" }),
            run.attempts.count == target.jobs.count, Set(run.attempts.map(\.jobID)) == Set(target.jobs.map(\.id)),
            Set(run.attempts.map(\.id)).count == run.attempts.count else { throw InvarError("INPUT_MISMATCH","Completed evidence cannot be reassociated to a different or incomplete captured scope") }
        var values: [EvidenceAssociation] = []
        for evidence in run.attempts {
            guard let job = target.jobs.first(where: { $0.id == evidence.jobID }), let old = run.associations.first(where: { $0.evidenceID == evidence.id }) else { throw InvarError("INVALID_RESULT","Reassociation lacks an original obligation/association") }
            var unknown = old.unknownBoundaries
            if target.input.dependencyStatus == "unknown" { unknown.append("Upstream project dependency closure remains unknown") }
            values.append(EvidenceAssociation.make(evidence: evidence,targetDescriptorID: job.descriptorID,changeRevisionID: nil,input: target.input,status: "matchesInputs",basis: "Exact current captured scope equals the original input/context/configuration/tool/profile declarations; prior unknown boundaries are retained",unknownBoundaries: unknown,reuseDecision: "identicalCapturedScope"))
        }
        return values
    }
}
