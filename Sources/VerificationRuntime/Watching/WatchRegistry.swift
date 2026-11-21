import Foundation
import VerificationCore

/// Owns workspace monitoring independently of Agent and transport sessions.
public actor WatchRegistry: WorkspaceOperationExecuting {
    private let repository: any VerificationRepository
    private let events: any SourceEventReading
    private let lifecycle: WatchLifecycle
    private let driver: WatchCycleDriver
    private let workspaceID: String
    private let epoch: String
    private let policy: WatchPolicy
    private var eventPump: Task<Void,Never>?
    private var cyclePump: Task<Void,Never>?
    private var cycles: [String:Task<Void,Never>] = [:]
    private var observed: [String:Int] = [:]
    private var nextProbe: [String:ContinuousClock.Instant] = [:]
    private var sourceVersion = 0
    private var dirtySince: ContinuousClock.Instant?
    private var changedAt: ContinuousClock.Instant?
    private var sourceReady = false
    private var sourceFailure: InvarError?
    private var cycleFailure: InvarError?
    private var cleanupFailure: InvarError?
    private var closed = false
    private var stopped = false
    public init(repository: any VerificationRepository,coordinator: any WorkspaceCoordinating,events: any SourceEventReading,probe: any WatchInputProbing,workspaceID: String,epoch: String,policy: WatchPolicy = .development) throws {
        try policy.validate()
        self.repository = repository; self.events = events; self.workspaceID = workspaceID; self.epoch = epoch; self.policy = policy
        let lifecycle = WatchLifecycle(repository: repository,coordinator: coordinator)
        self.lifecycle = lifecycle
        driver = WatchCycleDriver(repository: repository,coordinator: coordinator,probe: probe,lifecycle: lifecycle)
    }
    public func start() async throws {
        guard !closed, !stopped, eventPump == nil else { throw InvarError("INVALID_TRANSITION","Watch registry is already active or closed") }
        for watch in try await repository.watches(states: ["stopping"]) { _ = try await lifecycle.finishStop(watch.id) }
        eventPump = Task { await self.observeSource() }
        cyclePump = Task { await self.admitCycles() }
    }
    public func execute(_ demand: RunDemand,authority: OperationAuthority) async throws -> String {
        guard !stopped, cleanupFailure == nil, demand.principal == authority.principal else { throw InvarError("COORDINATOR_STOPPED","Watch control is closed or requires recovery") }
        switch demand.request {
        case .watch:
            guard !closed else { throw InvarError("COORDINATOR_STOPPED","Watch registration admission is closed") }
            return try await lifecycle.prepareRegistration(demand,authority: authority)
        case .stopWatch(let id): return try await stop(id,principal: authority.principal)
        default: throw InvarError("INVALID_REQUEST","Non-watch operation reached watch registry")
        }
    }
    func stop(_ id: String,principal: String,target: String = "stopped") async throws -> String {
        _ = try await lifecycle.beginStop(id,principal: principal,target: target)
        let task = cycles[id]; task?.cancel(); await task?.value
        let record = try await lifecycle.finishStop(id)
        observed.removeValue(forKey: id); nextProbe.removeValue(forKey: id)
        return record.id
    }
    public func available() -> Bool { sourceReady }
    public func diagnostics() -> [InvarError] { [sourceFailure,cycleFailure,cleanupFailure].compactMap { $0 } }
    private func observeSource() async {
        while !Task.isCancelled, !closed {
            do {
                let event = try await events.poll()
                try Task.checkCancellation()
                sourceReady = event.ready; sourceFailure = nil
                if event.invalidated {
                    try await invalidate(event.reason ?? "Source continuity requires resync")
                }
            } catch is CancellationError { return }
            catch {
                sourceReady = false; sourceFailure = Self.failure(error)
                do { try await invalidate("Source unavailable; observation continuity requires resync") }
                catch { cleanupFailure = Self.failure(error) }
            }
            do { try await Task.sleep(for: .seconds(policy.pollSeconds)) } catch { return }
        }
    }
    private func invalidate(_ reason: String) async throws {
        _ = try await repository.invalidateSource(workspaceID: workspaceID,epoch: epoch,reason: String(reason.prefix(256)))
        guard sourceVersion < Int.max else { throw InvarError("RESOURCE_LIMIT","Watch source version exhausted",exitCode: 6) }
        sourceVersion += 1
        let now = ContinuousClock.now
        if dirtySince == nil { dirtySince = now }
        changedAt = now
    }
    private func admitCycles() async {
        while !Task.isCancelled, !closed {
            do { try await tick() }
            catch is CancellationError { return }
            catch { cleanupFailure = Self.failure(error) }
            do { try await Task.sleep(for: .seconds(policy.pollSeconds)) } catch { return }
        }
    }
    private func tick() async throws {
        guard cleanupFailure == nil else { return }
        let watches = try await repository.watches(states: ["active","paused","stopping"])
        let ids = Set(watches.map(\.id))
        observed = observed.filter { ids.contains($0.key) }; nextProbe = nextProbe.filter { ids.contains($0.key) }
        for watch in watches {
            try Task.checkCancellation()
            if watch.state == "stopping" { _ = try await stop(watch.id,principal: watch.principal); continue }
            if watch.expiresAt <= Date().timeIntervalSince1970 { _ = try await stop(watch.id,principal: watch.principal,target: "expired"); continue }
            guard watch.state == "active" else { continue }
            do { try await repository.authorizeWatch(watch.id) }
            catch let failure as InvarError where failure.code == "POLICY_DENIED" {
                try await pause(watch,failure: failure); continue
            }
            try Task.checkCancellation()
            guard !closed else { return }
            guard sourceReady, cycles[watch.id] == nil, cycles.count < policy.maximumConcurrentCycles else { continue }
            let now = ContinuousClock.now, force = observed[watch.id] != sourceVersion
            if force, let changedAt, let dirtySince,
                changedAt.duration(to: now) < .seconds(policy.settleSeconds), dirtySince.duration(to: now) < .seconds(policy.maximumSettleSeconds) { continue }
            guard force || nextProbe[watch.id].map({ $0 <= now }) ?? true else { continue }
            observed[watch.id] = sourceVersion
            let id = watch.id
            cycles[id] = Task {
                var succeeded = false
                do { try await self.driver.run(id,force: force); succeeded = true }
                catch is CancellationError {}
                catch {
                    let failure = Self.failure(error)
                    if ["CLEANUP_FAILED","PERSISTENCE_FAILED","STORE_INTEGRITY","STORE_QUOTA","RECOVERY_BLOCKED"].contains(failure.code) { self.cleanupFailure = failure }
                    else { self.cycleFailure = failure }
                }
                self.finished(id,succeeded: succeeded)
            }
        }
        if watches.filter({ $0.state == "active" }).allSatisfy({ observed[$0.id] == sourceVersion }) { dirtySince = nil }
    }
    private func finished(_ id: String,succeeded: Bool) {
        cycles.removeValue(forKey: id)
        nextProbe[id] = ContinuousClock.now.advanced(by: .seconds(succeeded ? policy.probeSeconds : policy.retrySeconds))
    }
    private func pause(_ watch: WatchRecord,failure: InvarError) async throws {
        let paused = try await repository.pauseWatch(watch.id,failure: Self.failure(failure))
        guard paused.state == "paused" else { return }
        let task = cycles[watch.id]; task?.cancel(); await task?.value
        try await lifecycle.cancelChildren(paused)
        _ = try await repository.finishWatchPause(watch.id)
    }
    public func closeAdmission() async {
        closed = true
        await lifecycle.closeAdmission()
        eventPump?.cancel(); cyclePump?.cancel()
        await eventPump?.value; await cyclePump?.value
        let active = Array(cycles.values)
        for task in active { task.cancel() }
        for task in active { await task.value }
        eventPump = nil; cyclePump = nil
    }
    public func shutdown() async throws {
        if stopped { return }
        await closeAdmission()
        try await lifecycle.shutdown()
        if let cleanupFailure { throw InvarError("RECOVERY_BLOCKED","Watch cleanup failed: " + cleanupFailure.message,exitCode: 6) }
        stopped = true
    }
    private static func failure(_ error: any Error) -> InvarError {
        if let failure = error as? InvarError { return InvarError(String(failure.code.prefix(128)),String(failure.message.prefix(256)),exitCode: failure.exitCode) }
        return InvarError("WATCH_FAILED",String(String(describing: error).prefix(256)),exitCode: 7)
    }
}
