import FormalEvidence
import Foundation
import VerificationCore
import VerificationFormal

public actor FormalReaderRegistry: FormalReadServing {
    private struct Entry {
        let lease: FormalReadLease
        let reader: any FormalEvidenceReading
        let pinID: String
    }
    private let repository: any VerificationRepository
    private let workspaceID: String
    private let epoch: String
    private let policy: FormalReadPolicy
    private var entries: [String:Entry] = [:]
    private var closing: [String:Task<Void,any Error>] = [:]
    private var reservations = 0
    private var drainers: [CheckedContinuation<Void,Never>] = []
    private var stopped = false
    public init(repository: any VerificationRepository,workspaceID: String,epoch: String,policy: FormalReadPolicy = .development) throws {
        try policy.validate()
        self.repository = repository; self.workspaceID = workspaceID; self.epoch = epoch; self.policy = policy
    }
    public var activeCount: Int { entries.count + closing.count + reservations }
    public func query(_ query: FormalReadQuery,epoch: String) async throws -> FormalReadResult {
        guard !stopped, self.epoch == epoch else { throw InvarError("POLICY_DENIED","Formal reader is closed or belongs to another epoch",exitCode: 8) }
        do {
            switch query {
            case .open(let evidenceID,let reference,let budget): return .opened(try await open(evidenceID,reference: reference,budget: budget))
            case .catalog(let handle): let entry = try lookup(handle); return .catalog(try await entry.reader.catalog())
            case .graph(let handle,let query): let entry = try lookup(handle); return .graph(try await entry.reader.graph(query))
            case .trace(let handle,let query): let entry = try lookup(handle); return .trace(try await entry.reader.trace(query))
            case .origins(let handle,let query): let entry = try lookup(handle); return .origins(try await entry.reader.origins(query))
            case .document(let handle,let query): let entry = try lookup(handle); return .document(try await entry.reader.document(query))
            case .close(let handle):
                try await close(handle); return .closed
            }
        } catch let error as FormalEvidenceError { throw Self.failure(error) }
    }
    private func open(_ evidenceID: String,reference: EvidenceBundleReference,budget: EvidenceReadBudget) async throws -> FormalReadLease {
        try policy.accepts(budget); try await expire(); try Task.checkCancellation()
        guard !stopped, entries.count + closing.count + reservations < policy.maximumReaders else { throw InvarError("RESOURCE_LIMIT","Formal reader admission is closed or full",exitCode: 6) }
        reservations += 1; defer { finishReservation() }
        let evidence = try await repository.loadEvidence(evidenceID)
        let input = try await repository.inputReference(evidence.inputID)
        guard input.workspaceID == workspaceID,
            let artifact = evidence.artifacts.first(where: { $0.id == reference.id && $0.sha256 == reference.sha256 && $0.byteCount == reference.byteCount && $0.mediaType == "application/vnd.formal.evidence.sqlite" && $0.profile == "formal-evidence/1" }) else { throw InvarError("POLICY_DENIED","Bundle is not owned by this workspace evidence",exitCode: 8) }
        try Task.checkCancellation()
        guard !stopped else { throw InvarError("SESSION_CLOSED","Formal readers are draining") }
        let id = UUID().uuidString, expiry = Date().timeIntervalSince1970 + policy.leaseSeconds
        let pin = RetentionPin(id: id,ownerKind: "formalReader",ownerID: id,objectKind: "evidence",objectID: evidenceID,expiresAt: expiry + 60)
        try await repository.pin(pin)
        var opened: (any FormalEvidenceReading)?
        do {
            try Task.checkCancellation()
            let directory = try await repository.artifactRoot(artifact)
            let reader = try EvidenceBundleReader(root: directory.deletingLastPathComponent(),reference: reference,budget: budget)
            opened = reader
            try Task.checkCancellation()
            guard !stopped, expiry > Date().timeIntervalSince1970 else { throw InvarError("READ_LEASE_EXPIRED","Formal reader expired during open",exitCode: 6) }
            let lease = FormalReadLease(id: id,epoch: epoch,evidenceID: evidenceID,reference: reference,expiresAt: expiry)
            entries[id] = Entry(lease: lease,reader: reader,pinID: pin.id)
            return lease
        } catch {
            let original = error
            let cleanup = Task {
                if let opened { try await opened.shutdown() }
                try await repository.releasePin(pin.id)
            }
            do { try await cleanup.value } catch { throw InvarError("CLEANUP_FAILED","Formal open failed (\(original)); cleanup failed (\(error))") }
            throw original
        }
    }
    private func lookup(_ id: String) throws -> Entry {
        guard let value = entries[id], value.lease.expiresAt > Date().timeIntervalSince1970 else { throw InvarError("READ_LEASE_EXPIRED","Formal read lease is absent or expired",exitCode: 6) }
        return value
    }
    private func close(_ id: String) async throws {
        if let task = closing[id] { try await task.value; return }
        guard let entry = entries.removeValue(forKey: id) else { return }
        let repository = self.repository
        let task = Task { try await entry.reader.shutdown(); try await repository.releasePin(entry.pinID) }
        closing[id] = task
        try await task.value
        closing.removeValue(forKey: id)
    }
    private func finishReservation() {
        reservations -= 1
        if reservations == 0 {
            let pending = drainers; drainers.removeAll()
            for continuation in pending { continuation.resume() }
        }
    }
    public func expire() async throws {
        let now = Date().timeIntervalSince1970, expired = entries.values.filter { $0.lease.expiresAt <= now }.map { $0.lease.id }
        for id in expired { try await close(id) }
    }
    public func shutdown() async throws {
        stopped = true
        if reservations > 0 { await withCheckedContinuation { drainers.append($0) } }
        let ids = Array(entries.keys) + Array(closing.keys)
        var failures: [String] = []
        for id in ids {
            do { try await close(id) } catch { failures.append(String(describing: error).prefix(512).description) }
        }
        guard failures.isEmpty else { throw InvarError("CLEANUP_FAILED","Formal reader cleanup failed: " + failures.joined(separator: "; ")) }
    }
    private static func failure(_ error: FormalEvidenceError) -> InvarError {
        let code: String, exit: Int32
        switch error {
        case .limit: code = "RESOURCE_LIMIT"; exit = 6
        case .invalidCursor: code = "INVALID_CURSOR"; exit = 6
        case .closed: code = "READ_LEASE_EXPIRED"; exit = 6
        case .missing: code = "FORMAL_RECORD_NOT_FOUND"; exit = 4
        case .unsupported: code = "FORMAL_QUERY_UNSUPPORTED"; exit = 3
        case .incompatibleVersion: code = "FORMAL_SCHEMA_MISMATCH"; exit = 3
        case .integrity: code = "FORMAL_EVIDENCE_INTEGRITY"; exit = 7
        case .io: code = "FORMAL_EVIDENCE_IO"; exit = 7
        case .invalid: code = "INVALID_FORMAL_QUERY"; exit = 2
        }
        return InvarError(code,error.description,exitCode: exit)
    }
}
