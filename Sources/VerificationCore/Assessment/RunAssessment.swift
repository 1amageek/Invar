public enum RunAssessment {
    public static func accepts(_ evidence: VerificationEvidence, for job: any VerificationObligation, association: EvidenceAssociation) -> Bool {
        guard evidence.jobID == job.id, evidence.execution == "completed", (job.backend != "fuzz" && evidence.outcome == "holdsWithinScope" || job.backend == "fuzz" && evidence.outcome == "noViolationObservedWithinBudget" && job.acceptsFuzzBudget), association.evidenceID == evidence.id, association.applicability == "matchesInputs", evidence.adequacy == "completeWithinScope" else { return false }
        if job.backend == "project" { return evidence.domain == "projectContract" && evidence.translation == "notApplicable" }
        if job.backend == "formal" && evidence.domain == "generatedModel" { return job.acceptsUnvalidatedModel && evidence.translation == "unvalidated" }
        if ["native", "fuzz"].contains(job.backend) { return evidence.domain == "nativeExecution" && evidence.translation == "notApplicable" }
        return job.backend == "static" && evidence.domain == "architecture" && evidence.translation == "notApplicable"
    }
    public static func accepts(_ attempts: [VerificationEvidence], associations: [EvidenceAssociation], plan: SchedulingPlan) -> Bool {
        let required = plan.jobs.filter(\.required)
        guard !required.isEmpty, Set(attempts.map(\.jobID)).count == attempts.count else { return false }
        return required.allSatisfy { job in
            guard let evidence = attempts.first(where: { $0.jobID == job.id }), let association = associations.first(where: { $0.evidenceID == evidence.id }), association.input.semanticDigest == plan.input.semanticDigest else { return false }
            if evidence.inputID != plan.input.id {
                guard let key = job.executionKey, key == evidence.executionKey, association.targetDescriptorID == job.descriptorID else { return false }
            }
            return accepts(evidence,for: job,association: association)
        }
    }
}
