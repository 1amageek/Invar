import Foundation
import VerificationCore

public actor ResourcePool: WorkspaceResourceAdmitting {
    private struct Waiting {
        let request: ResourceRequest
        let continuation: CheckedContinuation<Void,any Error>
        var bypasses: Int = 0
    }
    private let policy: SchedulingPolicy
    private var queue: [Waiting] = []
    private var active: [String:ResourceRequest] = [:]
    private var stopped = false
    public init(policy: SchedulingPolicy) { self.policy = policy }
    public func acquire(_ request: ResourceRequest) async throws {
        try policy.validate()
        guard !stopped else { throw InvarError("COORDINATOR_STOPPED","Resource pool is stopped") }
        guard request.memoryMiB > 0, request.memoryMiB <= policy.memoryMiB,
            request.processes >= 0, request.processes <= policy.maximumProcesses,
            request.scratchBytes >= 0, request.scratchBytes <= policy.maximumScratchBytes else { throw InvarError("RESOURCE_LIMIT","Job cannot fit shared resource policy",exitCode: 6) }
        guard active[request.id] == nil, !queue.contains(where: { $0.request.id == request.id }) else { throw InvarError("IDEMPOTENCY_CONFLICT","Resource owner already has an admitted or queued request") }
        guard queue.count < policy.maximumReadyJobs else { throw InvarError("RESOURCE_LIMIT","Ready-job capacity exhausted",exitCode: 6) }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                queue.append(Waiting(request: request,continuation: continuation)); drain()
            }
        } onCancel: { Task { await self.cancel(request.id) } }
    }
    private func cancel(_ id: String) {
        if let index = queue.firstIndex(where: { $0.request.id == id }) {
            queue.remove(at: index).continuation.resume(throwing: CancellationError()); drain()
        }
    }
    public func release(_ id: String) { active.removeValue(forKey: id); drain() }
    private func drain() {
        while active.count < policy.maximumWorkers, !queue.isEmpty {
            let selected: Int
            if queue[0].bypasses >= policy.maximumPriorityBypasses { selected = 0 }
            else { selected = queue.indices.min { queue[$0].request.priority < queue[$1].request.priority }! }
            let request = queue[selected].request
            let memory = active.values.reduce(0) { $0 + $1.memoryMiB }
            let processes = active.values.reduce(0) { $0 + $1.processes }
            let scratch = active.values.reduce(0) { $0 + $1.scratchBytes }
            guard request.memoryMiB <= policy.memoryMiB - memory, request.processes <= policy.maximumProcesses - processes,
                request.scratchBytes <= policy.maximumScratchBytes - scratch else { return }
            let waiting = queue.remove(at: selected)
            for index in queue.indices { queue[index].bypasses = min(policy.maximumPriorityBypasses,queue[index].bypasses + 1) }
            active[request.id] = request; waiting.continuation.resume()
        }
    }
    public func status(interests: Int) -> SchedulingStatus {
        SchedulingStatus(activeExecutions: active.count,waitingExecutions: queue.count,interests: interests,
            reservedMemoryMiB: active.values.reduce(0) { $0 + $1.memoryMiB },reservedProcesses: active.values.reduce(0) { $0 + $1.processes },reservedScratchBytes: active.values.reduce(0) { $0 + $1.scratchBytes })
    }
    public func shutdown() {
        stopped = true
        let waiting = queue; queue.removeAll()
        for entry in waiting { entry.continuation.resume(throwing: CancellationError()) }
    }
}
