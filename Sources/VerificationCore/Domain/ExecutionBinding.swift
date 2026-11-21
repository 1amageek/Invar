import Foundation

public enum ExecutionBinding {
    public static func key(_ descriptor: JobDescriptor) throws -> String? {
        try PlanValidation.descriptor(descriptor)
        let job = descriptor.job
        if job.backend == "project" { return nil }
        if job.backend == "static" && !descriptor.input.graphClosureComplete { return nil }
        guard job.backend == "static" || job.toolchainIdentity != nil else { return nil }
        let jobBytes = try Canonical.encode(job)
        let budgetBytes = try Canonical.encode(descriptor.budget)
        return Canonical.parts("invar.scoped-execution/2",[descriptor.input.workspaceID,descriptor.input.contextDigest,
            job.backend == "static" ? descriptor.input.graphDigest : "enforced-standalone-profile",
            descriptor.executorIdentity,Canonical.digest(jobBytes),Canonical.digest(budgetBytes)])
    }
    public static func descriptor(plan: VerificationPlan,job: VerificationJob) -> JobDescriptor {
        JobDescriptor(planID: plan.id,input: plan.body.input,job: job,executorIdentity: plan.body.executorIdentity,budget: plan.body.budget)
    }
}
