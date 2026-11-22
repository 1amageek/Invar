import Foundation
import VerificationCore

public actor VerificationScheduler: VerificationScheduling {
    private let repository: any VerificationRepository
    private let applicability: (any InputApplicabilityChecking)?
    private let executor: SharedJobExecutor
    private var stopped = false
    public init(backend: any VerificationBackend,repository: any VerificationRepository,applicability: (any InputApplicabilityChecking)? = nil,policy: SchedulingPolicy = .development,resources: (any WorkspaceResourceAdmitting)? = nil) {
        self.repository = repository; self.applicability = applicability
        executor = SharedJobExecutor(backend: backend,repository: repository,policy: policy,resources: resources)
    }
    public func run(_ planID: String,replay: Bool = false,persist: Bool = true,demandID: String? = nil) async throws -> VerificationRun {
        guard !stopped else { throw InvarError("COORDINATOR_STOPPED","Scheduler is stopped") }
        let plan = try await repository.schedulingPlan(planID)
        var pending = plan.jobs, evidence: [VerificationEvidence] = [], running = 0, memory = 0
        let deadline = ContinuousClock.now.advanced(by: .seconds(plan.budget.runTimeoutSeconds))
        try await withThrowingTaskGroup(of: (JobReference,VerificationEvidence).self) { group in
            while !pending.isEmpty || running > 0 {
                if Task.isCancelled || ContinuousClock.now >= deadline {
                    evidence.append(contentsOf: pending.map { ExecutionFailure.evidence($0,inputID: plan.input.id,execution: Task.isCancelled ? "cancelled" : "timeout",detail: "Whole-run deadline/cancellation before admission") })
                    pending.removeAll(); group.cancelAll()
                }
                var admitted = true
                while admitted && running < plan.budget.maximumWorkers {
                    admitted = false
                    for index in pending.indices {
                        let job = pending[index]
                        if job.memoryMiB > plan.budget.memoryMiB {
                            evidence.append(ExecutionFailure.evidence(job,inputID: plan.input.id,execution: "blocked",detail: "Job cannot fit its memory admission budget")); pending.remove(at: index); admitted = true; break
                        }
                        let completed = Set(evidence.filter { value in
                            guard let predecessor = plan.jobs.first(where: { $0.id == value.jobID }) else { return false }
                            let association = EvidenceAssociation.make(evidence: value,changeRevisionID: nil,input: plan.input,status: "matchesInputs",basis: "Exact fixed prerequisite",unknownBoundaries: [],reuseDecision: "prerequisite")
                            return RunAssessment.accepts(value,for: predecessor,association: association)
                        }.map(\.jobID))
                        if Set(job.dependencies).isSubset(of: completed), job.memoryMiB <= plan.budget.memoryMiB - memory {
                            pending.remove(at: index); running += 1; memory += job.memoryMiB; admitted = true
                            let executor = self.executor
                            let remaining = ContinuousClock.now.duration(to: deadline).components
                            let seconds = max(0.001,Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
                            group.addTask {
                                do {
                                    let value = try await BoundedOperation.run(seconds: seconds) {
                                        try await executor.execute(reference: job,input: plan.input,budget: plan.budget,demandID: demandID,replay: replay,priority: replay ? 0 : 1)
                                    }
                                    return (job,value)
                                } catch { return (job,ExecutionFailure.evidence(job,inputID: plan.input.id,error: error)) }
                            }
                            break
                        }
                    }
                }
                if running > 0, let (job,result) = try await group.next() {
                    running -= 1; memory -= job.memoryMiB; evidence.append(result)
                } else if running == 0 && !pending.isEmpty {
                    evidence.append(contentsOf: pending.map { ExecutionFailure.evidence($0,inputID: plan.input.id,execution: "blocked",detail: "Unsuccessful job prerequisites") }); pending.removeAll()
                }
            }
        }
        var comparison = InputComparison(target: nil,status: "unknown",basis: "No current input comparison"), diagnostics = plan.diagnostics
        if let applicability, !Task.isCancelled, ContinuousClock.now < deadline {
            do {
                let remaining = ContinuousClock.now.duration(to: deadline).components
                let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
                comparison = try await BoundedOperation.run(seconds: seconds) { try await applicability.applicability(of: plan) }
                guard ["matchesInputs","stale","unmatched","unknown"].contains(comparison.status), comparison.status != "matchesInputs" || comparison.target?.semanticDigest == plan.input.semanticDigest else { throw InvarError("INVALID_APPLICABILITY","Current-input comparison lacks exact binding") }
            } catch { comparison = InputComparison(target: nil,status: "unknown",basis: "Current comparison failed"); diagnostics.append("Current input validation unavailable: " + String(describing: error)) }
        }
        var associations: [EvidenceAssociation] = []
        for value in evidence {
            guard let job = plan.jobs.first(where: { $0.id == value.jobID }) else { throw InvarError("INVALID_RESULT","Unknown job result") }
            let id = job.descriptorID
            let target = comparison.target ?? plan.input
            associations.append(EvidenceAssociation.make(evidence: value,targetDescriptorID: target.id == plan.input.id ? id : nil,changeRevisionID: nil,input: target,status: comparison.status,basis: comparison.basis,unknownBoundaries: comparison.unknownBoundaries + (comparison.target == nil ? ["No current target binding"] : []),reuseDecision: value.inputID == plan.input.id ? "originalExecution" : "equalCompleteScopedInputs"))
        }
        let run = VerificationRun(id: UUID().uuidString,planID: plan.id,attempts: evidence.sorted { $0.jobID < $1.jobID },associations: associations.sorted { $0.evidenceID < $1.evidenceID },accepted: RunAssessment.accepts(evidence,associations: associations,plan: plan),diagnostics: diagnostics)
        if persist { try await repository.saveRun(run) }
        return run
    }
    public func status() async -> SchedulingStatus { await executor.status() }
    public func shutdown() async { stopped = true; await executor.shutdown() }
}
