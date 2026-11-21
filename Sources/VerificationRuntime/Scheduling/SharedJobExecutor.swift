import Foundation
import VerificationCore

actor SharedJobExecutor {
    private struct Entry {
        let id: String
        let queued: Task<ExecutionRecord,any Error>
        let reference: JobReference
        let input: VerificationInput
        let budget: RunBudget
        var work: Task<Void,Never>?
        var interests: Set<String>
        var waiters: [String:CheckedContinuation<VerificationEvidence,any Error>]
        var result: Result<VerificationEvidence,any Error>?
    }
    private let backend: any VerificationBackend
    private let repository: any VerificationRepository
    private let policy: SchedulingPolicy
    private let pool: any WorkspaceResourceAdmitting
    private var entries: [String:Entry] = [:]
    private var releases: [String:Task<Void,any Error>] = [:]
    private var stopped = false
    init(backend: any VerificationBackend,repository: any VerificationRepository,policy: SchedulingPolicy,resources: (any WorkspaceResourceAdmitting)?) {
        self.backend = backend; self.repository = repository; self.policy = policy; pool = resources ?? ResourcePool(policy: policy)
    }
    func execute(reference: JobReference,input: VerificationInput,budget: RunBudget,demandID: String?,nativeExecutionAllowed: Bool,replay: Bool,priority: Int) async throws -> VerificationEvidence {
        try Task.checkCancellation()
        guard !stopped else { throw InvarError("COORDINATOR_STOPPED","Shared executor stopped") }
        if !replay, let key = reference.executionKey, let cached = try await repository.reusableEvidence(key: key) {
            try Task.checkCancellation()
            if let demandID {
                guard let executionID = cached.executionID else { throw InvarError("STORE_INTEGRITY","Reusable evidence has no physical execution") }
                try await repository.attachExecution(executionID,to: demandID,jobID: reference.id)
            }
            return cached
        }
        try Task.checkCancellation()
        guard !stopped else { throw InvarError("COORDINATOR_STOPPED","Shared executor stopped during cache lookup") }
        let sharingKey = !replay ? reference.executionKey ?? UUID().uuidString : UUID().uuidString
        let interest = UUID().uuidString
        let queued: Task<ExecutionRecord,any Error>
        if var entry = entries[sharingKey] {
            entry.interests.insert(interest); entries[sharingKey] = entry; queued = entry.queued
        } else {
            guard entries.count < policy.maximumReadyJobs + policy.maximumWorkers else { throw InvarError("RESOURCE_LIMIT","Shared execution metadata capacity exhausted",exitCode: 6) }
            let id = UUID().uuidString, repository = self.repository
            queued = Task {
                let row = ExecutionRecord(id: id,descriptorID: reference.descriptorID,inputKey: reference.executionKey ?? id,planID: reference.planID,jobID: reference.id,state: "queued",revision: 1,evidenceID: nil,failure: nil)
                try await repository.saveExecution(row,expectedRevision: 0)
                return row
            }
            entries[sharingKey] = Entry(id: id,queued: queued,reference: reference,input: input,budget: budget,work: nil,interests: [interest],waiters: [:],result: nil)
        }
        defer { releases.removeValue(forKey: interest) }
        return try await withTaskCancellationHandler {
            do {
                let row = try await queued.value
                try Task.checkCancellation()
                if let demandID { try await repository.attachExecution(row.id,to: demandID,jobID: reference.id) }
                try Task.checkCancellation()
                let value = try await withCheckedThrowingContinuation { continuation in
                    confirm(sharingKey,interest: interest,continuation: continuation,queued: row,reference: reference,input: input,budget: budget,nativeExecutionAllowed: nativeExecutionAllowed,priority: priority)
                }
                try Task.checkCancellation()
                return value
            } catch {
                try await cancel(sharingKey,interest: interest)
                throw error
            }
        } onCancel: { Task { _ = await self.cancelResult(sharingKey,interest: interest) } }
    }
    private func confirm(_ key: String,interest: String,continuation: CheckedContinuation<VerificationEvidence,any Error>,queued: ExecutionRecord,reference: JobReference,input: VerificationInput,budget: RunBudget,nativeExecutionAllowed: Bool,priority: Int) {
        guard var entry = entries[key], entry.interests.contains(interest), !stopped else { continuation.resume(throwing: CancellationError()); return }
        if let result = entry.result {
            entry.interests.remove(interest)
            if entry.interests.isEmpty { entries.removeValue(forKey: key) } else { entries[key] = entry }
            continuation.resume(with: result)
            return
        }
        entry.waiters[interest] = continuation
        if entry.work == nil {
            let repository = self.repository, backend = self.backend, pool = self.pool, policy = self.policy
            let reference = entry.reference, input = entry.input, budget = entry.budget
            let request = ResourceRequest(id: queued.id,memoryMiB: reference.memoryMiB,processes: budget.maximumProcesses,scratchBytes: budget.maximumWorkspaceBytes,priority: priority)
            entry.work = Task {
                let result: Result<VerificationEvidence,any Error>
                do { result = .success(try await Self.perform(queued: queued,reference: reference,input: input,budget: budget,request: request,nativeExecutionAllowed: nativeExecutionAllowed,repository: repository,backend: backend,pool: pool,policy: policy)) }
                catch { result = .failure(error) }
                self.finished(key,id: queued.id,result: result)
            }
        }
        entries[key] = entry
    }
    private func finished(_ key: String,id: String,result: Result<VerificationEvidence,any Error>) {
        guard var entry = entries[key], entry.id == id else { return }
        // Preparing interests retain the terminal result until their durable
        // attachment finishes; completion cannot strand a late continuation.
        let waiters = entry.waiters
        entry.interests.subtract(waiters.keys); entry.waiters.removeAll(); entry.result = result
        if entry.interests.isEmpty { entries.removeValue(forKey: key) } else { entries[key] = entry }
        for waiter in waiters.values { waiter.resume(with: result) }
    }
    private func cancelResult(_ key: String,interest: String) async -> Result<Void,any Error> {
        do { try await cancel(key,interest: interest); return .success(()) } catch { return .failure(error) }
    }
    private func cancel(_ key: String,interest: String) async throws {
        if let pending = releases[interest] { try await pending.value; return }
        guard var entry = entries[key], entry.interests.remove(interest) != nil else { return }
        let continuation = entry.waiters.removeValue(forKey: interest)
        let last = entry.interests.isEmpty
        if last { entries.removeValue(forKey: key); entry.work?.cancel() } else { entries[key] = entry }
        let repository = self.repository
        let release = Task<Void,any Error> {
            do {
                if last {
                    if let work = entry.work { await work.value }
                    else if case .success(let row) = await entry.queued.result {
                        let terminal = ExecutionRecord(id: row.id,descriptorID: row.descriptorID,inputKey: row.inputKey,planID: row.planID,jobID: row.jobID,state: "cancelled",revision: 2,evidenceID: nil,failure: InvarError("CANCELLED","Last interest ended before worker admission",exitCode: 130))
                        try await repository.saveExecution(terminal,expectedRevision: 1)
                    }
                }
                continuation?.resume(throwing: CancellationError())
            } catch { continuation?.resume(throwing: error); throw error }
        }
        releases[interest] = release
        try await release.value
    }
    func status() async -> SchedulingStatus { await pool.status(interests: entries.values.reduce(0) { $0 + $1.interests.count }) }
    func shutdown() async {
        stopped = true; await pool.shutdown()
        let interests = entries.flatMap { key,entry in entry.interests.map { (key,$0) } }
        for (key,interest) in interests { _ = await cancelResult(key,interest: interest) }
        let pending = Array(releases.values)
        for release in pending { _ = await release.result }
    }
    private nonisolated static func perform(queued: ExecutionRecord,reference: JobReference,input: VerificationInput,budget: RunBudget,request: ResourceRequest,nativeExecutionAllowed: Bool,repository: any VerificationRepository,backend: any VerificationBackend,pool: any WorkspaceResourceAdmitting,policy: SchedulingPolicy) async throws -> VerificationEvidence {
        var revision = 1, reserved = false
        do { try await pool.acquire(request) }
        catch { try await fail(queued,revision: revision,error: error,repository: repository); throw error }
        defer { await pool.release(queued.id) }
        do {
            try Task.checkCancellation()
            let reservation = StorageReservation(id: queued.id,relativeRoot: "runs/" + queued.id,maximumBytes: budget.maximumWorkspaceBytes,maximumFiles: policy.maximumScratchFiles)
            try await repository.reserve(reservation); reserved = true
            // Only an admitted physical worker materializes the sealed descriptor.
            let descriptor = try await repository.loadDescriptor(reference.descriptorID)
            let loaded = try JobReference(descriptor)
            guard loaded == reference, descriptor.input == input, descriptor.budget == budget else { throw InvarError("STORE_INTEGRITY","Admitted descriptor differs from sealed scheduling metadata") }
            let running = ExecutionRecord(id: queued.id,descriptorID: queued.descriptorID,inputKey: queued.inputKey,planID: queued.planID,jobID: queued.jobID,state: "running",revision: 2,evidenceID: nil,failure: nil)
            try await repository.saveExecution(running,expectedRevision: 1); revision = 2
            let evidence: VerificationEvidence
            let output = try await repository.outputRoot(for: queued.id)
            do {
                try Task.checkCancellation()
                let inputRoot = try await repository.inputLocation(input)
                let preparation: URL?
                if let unit = descriptor.job.compilation { preparation = try await repository.preparationOutput(unit.id) } else { preparation = nil }
                try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
                let context = BackendContext(descriptor: descriptor,descriptorID: reference.descriptorID,inputRoot: inputRoot,outputRoot: output,compilationRoot: preparation,timeoutSeconds: budget.timeoutSeconds,ownerPID: ProcessInfo.processInfo.processIdentifier,nativeExecutionAllowed: nativeExecutionAllowed)
                let value = try await BoundedOperation.run(seconds: context.timeoutSeconds) { try await backend.execute(context) }
                try PlanValidation.evidence(value,job: reference)
                guard value.inputID == input.id else { throw InvarError("INVALID_RESULT","Worker returned another original input") }
                let sealed = value.binding(executionID: queued.id,descriptorID: reference.descriptorID,executionKey: reference.executionKey)
                try await repository.adoptArtifacts(sealed,from: output,maximumBytes: budget.maximumWorkspaceBytes)
                evidence = sealed
            } catch { evidence = ExecutionFailure.evidence(reference,inputID: input.id,error: error).binding(executionID: queued.id,descriptorID: reference.descriptorID,executionKey: reference.executionKey) }
            let terminal = ExecutionRecord(id: queued.id,descriptorID: queued.descriptorID,inputKey: queued.inputKey,planID: queued.planID,jobID: queued.jobID,state: "completed",revision: 3,evidenceID: evidence.id,failure: nil)
            do { try await repository.completeExecution(terminal,evidence: evidence,expectedRevision: 2) }
            catch {
                // Evidence publication can exhaust ordinary quota. Preserve the
                // failure through reserved terminal capacity before releasing CAS.
                try await fail(queued,revision: revision,error: error,repository: repository); revision = 3
                throw error
            }
            revision = 3
            try await repository.releaseReservation(queued.id); reserved = false
            return evidence
        } catch {
            let original = error
            if revision < 3 { try await fail(queued,revision: revision,error: original,repository: repository) }
            if reserved {
                do { try await repository.releaseReservation(queued.id) }
                catch { throw InvarError("CLEANUP_FAILED","Execution failed (\(original)); reservation release failed (\(error))") }
            }
            throw original
        }
    }
    private nonisolated static func fail(_ queued: ExecutionRecord,revision: Int,error: any Error,repository: any VerificationRepository) async throws {
        let failure = error as? InvarError ?? InvarError(error is CancellationError ? "CANCELLED" : "EXECUTION_FAILED",String(describing: error),exitCode: error is CancellationError ? 130 : 7)
        let bounded = InvarError(String(failure.code.prefix(128)),String(failure.message.prefix(1024)),exitCode: failure.exitCode)
        let terminal = ExecutionRecord(id: queued.id,descriptorID: queued.descriptorID,inputKey: queued.inputKey,planID: queued.planID,jobID: queued.jobID,state: error is CancellationError ? "cancelled" : "failed",revision: revision+1,evidenceID: nil,failure: bounded)
        try await repository.saveExecution(terminal,expectedRevision: revision)
    }
}
