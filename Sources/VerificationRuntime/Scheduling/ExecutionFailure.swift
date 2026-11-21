import Foundation
import VerificationCore

enum ExecutionFailure {
    static func evidence(_ job: any VerificationObligation,inputID: String,error: any Error) -> VerificationEvidence {
        let typed = error as? InvarError
        let status = error is CancellationError ? "cancelled" : typed?.code == "TIMEOUT" ? "timeout" : typed?.exitCode == 6 ? "resourceLimited" : (typed?.code.hasPrefix("BLOCKED") == true || typed?.exitCode == 8) ? "blocked" : typed?.exitCode == 3 ? "unsupported" : "toolError"
        return evidence(job,inputID: inputID,execution: status,detail: String(describing: error),code: typed?.code ?? (error is CancellationError ? "CANCELLED" : "BACKEND_FAILED"))
    }
    static func evidence(_ job: any VerificationObligation,inputID: String,execution: String,detail: String,code: String? = nil) -> VerificationEvidence {
        let date = Canonical.date()
        return VerificationEvidence(inputID: inputID,jobID: job.id,execution: execution,outcome: "notEvaluated",domain: job.backend == "project" ? "projectContract" : job.backend == "static" ? "architecture" : ["modelGeneration","formal"].contains(job.backend) ? "generatedModel" : "nativeExecution",translation: ["modelGeneration","formal"].contains(job.backend) ? "unvalidated" : "notApplicable",scope: "Not evaluated",adequacy: "unknown",detail: detail,diagnosticCode: code,startedAt: date,finishedAt: date)
    }
}
