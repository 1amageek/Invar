import Darwin
import CryptoKit
import Foundation
import VerificationCore

public actor SQLiteVerificationStore: VerificationRepository {
    public let root: URL
    public let policy: StorePolicy
    var activeEpoch: String?
    var resourceRevision = 0
    var diskReads: [UUID:Task<StoreDiskInventory.Snapshot, any Error>] = [:]
    var closing = false
    var inputWrites = 0
    var inputWriteWaiters: [CheckedContinuation<Void,Never>] = []
    var shutdownTask: Task<Void,any Error>?
    let database: SQLiteConnection
    public init(root: URL,policy: StorePolicy = .development) throws {
        try policy.validate()
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { throw InvarError("UNSAFE_STORE", "Store must be an owned private non-symlink directory", exitCode: 8) }
        guard root.resolvingSymlinksInPath().path == root.standardizedFileURL.path else { throw InvarError("UNSAFE_STORE", "Store path contains a symlink", exitCode: 8) }
        for name in ["verification.sqlite", "verification.sqlite-wal", "verification.sqlite-shm"] {
            var entry = stat()
            let result = lstat(root.appendingPathComponent(name).path, &entry)
            guard result != 0 && errno == ENOENT || result == 0 && (entry.st_mode & S_IFMT) == S_IFREG && entry.st_uid == getuid() else { throw InvarError("UNSAFE_STORE", "Unsafe database file", exitCode: 8) }
        }
        self.policy = policy
        self.root = root.standardizedFileURL
        database = try SQLiteConnection(root.appendingPathComponent("verification.sqlite").path)
        let pageSize = try database.scalar("PRAGMA page_size")
        guard pageSize > 0 else { throw InvarError("STORE_INTEGRITY","Invalid SQLite page size") }
        let requestedPages = policy.maximumDatabaseBytes / pageSize
        let acceptedPages = try database.scalar("PRAGMA max_page_count=" + String(requestedPages))
        guard acceptedPages == requestedPages else { throw InvarError("STORE_QUOTA","Requested database ceiling is below existing allocation",exitCode: 6) }
        database.configure(policy)
        let policyBytes = try Canonical.encode(policy)
        if let existing = try database.load("metadata",id: "store-policy") {
            guard existing == policyBytes else { throw InvarError("IMMUTABLE_CONFLICT","Persisted Store policy differs; use a new state directory") }
        } else { try database.insert("metadata",id: "store-policy",bytes: policyBytes) }
        for name in ["inputs", "runs", "prepared", "artifacts"] { try manager.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }
    public func saveInput(_ capture: CapturedWorkspace) async throws -> String {
        try ensureAccepting()
        if let policy = try loadPolicy(), policy.workspaceID != capture.inventory.workspaceID { throw InvarError("INPUT_MISMATCH","Capture belongs to another host workspace") }
        inputWrites += 1; defer { finishInputWrite() }
        let manifest = try Canonical.encode(capture.inventory)
        guard manifest.count <= 64 * 1024 * 1024,
            Set(capture.files.keys) == Set(capture.inventory.inputs.map(\.path)), capture.files.count == capture.inventory.inputs.count else { throw InvarError("INCOMPLETE_INPUT","Capture manifest/files exceed their bounded exact profile") }
        var total = 0, directories: Set<String> = ["","payload"]
        for item in capture.inventory.inputs {
            _ = try Canonical.relative(item.path)
            guard let bytes = capture.files[item.path], item.byteCount >= 0, item.byteCount <= 5 * 1024 * 1024,
                bytes.count == item.byteCount, Canonical.digest(bytes) == item.digest, bytes.count <= 256 * 1024 * 1024 - total else { throw InvarError("INPUT_MISMATCH","Input size/digest differs from bounded capture") }
            total += bytes.count
            var parent = "payload"
            for part in item.path.split(separator: "/").dropLast() { parent += "/" + part; directories.insert(parent) }
        }
        let id = Canonical.digest(manifest)
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("inputs/" + id).path) { return try persistInput(capture,manifest: manifest,reservation: nil) }
        let reservationID = UUID().uuidString
        let reservation = StorageReservation(id: reservationID,relativeRoot: "preparing/" + reservationID,maximumBytes: max(1,total + manifest.count),maximumFiles: directories.count + capture.files.count + 1)
        try await reserve(reservation)
        do {
            try Task.checkCancellation()
            let id = try persistInput(capture,manifest: manifest,reservation: reservation)
            try releaseOwnedReservation(reservation.id)
            return id
        } catch {
            do { try releaseOwnedReservation(reservation.id) }
            catch let cleanup { throw InvarError("CLEANUP_FAILED","Input publication failed (\(error)); reservation cleanup failed (\(cleanup))") }
            throw error
        }
    }
    private func finishInputWrite() {
        inputWrites -= 1
        if inputWrites == 0 {
            let waiting = inputWriteWaiters; inputWriteWaiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
    }
    private func persistInput(_ capture: CapturedWorkspace,manifest: Data,reservation: StorageReservation?) throws -> String {
        try database.ensureOpen()
        let id = try Canonical.identity(capture.inventory)
        guard Set(capture.files.keys) == Set(capture.inventory.inputs.map(\.path)), capture.inventory.inputs.count == capture.files.count else { throw InvarError("INCOMPLETE_INPUT", "Inventory and original files differ") }
        let destination = root.appendingPathComponent("inputs/" + id)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try inputRoot(id)
            let reference = try VerificationInput.reference(capture.inventory)
            let referenceBytes = try Canonical.encode(reference)
            try database.insert("input",id: id,bytes: referenceBytes)
            return id
        }
        guard let reservation else { throw InvarError("INPUT_MISMATCH","New input lacks its admitted reservation") }
        let staging = root.appendingPathComponent(reservation.relativeRoot)
        let manager = FileManager.default
        try manager.createDirectory(at: staging.appendingPathComponent("payload"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            var total = 0
            for item in capture.inventory.inputs {
                try Task.checkCancellation()
                _ = try Canonical.relative(item.path)
                guard let bytes = capture.files[item.path], bytes.count == item.byteCount, Canonical.digest(bytes) == item.digest else { throw InvarError("INPUT_MISMATCH", "Input bytes do not match inventory") }
                total += bytes.count
                guard total <= 256 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT", "Input exceeds 256 MiB", exitCode: 6) }
                let path = staging.appendingPathComponent("payload").appendingPathComponent(item.path)
                try manager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try durableWrite(bytes, to: path)
            }
            try durableWrite(manifest, to: staging.appendingPathComponent("inventory.json"))
            var directories = Set([staging.path, staging.appendingPathComponent("payload").path])
            for item in capture.inventory.inputs {
                var parent = staging.appendingPathComponent("payload").appendingPathComponent(item.path).deletingLastPathComponent()
                while parent.path.hasPrefix(staging.path) { directories.insert(parent.path); parent.deleteLastPathComponent() }
            }
            for path in directories.sorted(by: { $0.count > $1.count }) { try synchronizeDirectory(URL(fileURLWithPath: path)) }
            try Task.checkCancellation()
            var published = true
            do { try manager.moveItem(at: staging, to: destination) }
            catch {
                guard manager.fileExists(atPath: destination.path) else { throw error }
                _ = try inputRoot(id); published = false
                if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
            }
            try synchronizeDirectory(destination.deletingLastPathComponent())
            let reference = try VerificationInput.reference(capture.inventory)
            let referenceBytes = try Canonical.encode(reference)
            try transaction {
                try database.insert("input",id: id,bytes: referenceBytes)
                if published { try transferOwnership(reservation: reservation,relativeRoot: "inputs/" + id,objectKind: "input",objectID: id) }
            }
            return id
        } catch {
            if manager.fileExists(atPath: staging.path) { do { try manager.removeItem(at: staging) } catch let cleanup { throw InvarError("CLEANUP_FAILED", "Capture failed (\(error)); cleanup failed (\(cleanup))") } }
            throw error
        }
    }
    public func inputLocation(_ input: VerificationInput) throws -> URL {
        try ensureAccepting()
        let reference = try inputReference(input.id)
        guard reference == input else { throw InvarError("INPUT_MISMATCH","Worker input reference differs") }
        let payload = root.appendingPathComponent("inputs/" + input.id + "/payload")
        let attributes = try payload.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true, payload.standardizedFileURL.path == payload.resolvingSymlinksInPath().path else { throw InvarError("UNSAFE_STORE","Unsafe worker input directory",exitCode: 8) }
        // Workers audit the exact bytes they consume against the sealed descriptor;
        // the control actor does not decode/hash the entire capture for every job.
        return payload
    }
    public func inputRoot(_ id: String) throws -> URL {
        try ensureAccepting()
        try database.ensureOpen()
        try safeID(id)
        let directory = root.appendingPathComponent("inputs/" + id)
        let bytes = try bounded(directory.appendingPathComponent("inventory.json"), maximum: 64 * 1024 * 1024)
        let inventory = try JSONDecoder().decode(ScopeInventory.self, from: bytes)
        guard Set(inventory.inputs.map(\.path)).count == inventory.inputs.count,
            inventory.inputs.allSatisfy({ $0.byteCount >= 0 && $0.byteCount <= 5 * 1024 * 1024 }) else { throw InvarError("STORE_INTEGRITY", "Invalid input catalog") }
        guard try Canonical.identity(inventory) == id else { throw InvarError("INPUT_MISMATCH", "Sealed inventory identity changed") }
        let payload = directory.appendingPathComponent("payload")
        for item in inventory.inputs {
            _ = try Canonical.relative(item.path)
            let path = payload.appendingPathComponent(item.path)
            guard path.resolvingSymlinksInPath().path == path.standardizedFileURL.path else { throw InvarError("ARTIFACT_OUTSIDE_ROOT", "Sealed input contains a symlink", exitCode: 8) }
            let value = try bounded(path, maximum: max(item.byteCount, 1))
            guard value.count == item.byteCount && Canonical.digest(value) == item.digest else { throw InvarError("INPUT_MISMATCH", "Sealed source changed: \(item.path)") }
        }
        return payload
    }
    public func inventory(_ input: VerificationInput) throws -> ScopeInventory {
        try ensureAccepting()
        try database.ensureOpen(); try safeID(input.id)
        let path = root.appendingPathComponent("inputs/" + input.id + "/inventory.json")
        let bytes = try bounded(path,maximum: 64 * 1024 * 1024)
        let inventory = try JSONDecoder().decode(ScopeInventory.self,from: bytes)
        let reference = try VerificationInput.reference(inventory)
        guard reference == input else { throw InvarError("INPUT_MISMATCH","Sealed catalog differs from fixed input reference") }
        return inventory
    }
    public func preparationOutput(_ id: String) throws -> URL {
        try ensureAccepting()
        try database.ensureOpen(); try safeID(id)
        return root.appendingPathComponent("prepared/" + id)
    }
    public func loadPreparation(_ id: String) throws -> PreparedFormalUnit? {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("preparation",id: id) else { return nil }
        let value = try JSONDecoder().decode(PreparedFormalUnit.self,from: bytes)
        guard value.id == id else { throw InvarError("STORE_INTEGRITY","Prepared unit identity differs") }
        try validatePreparation(value); return value
    }
    public func savePreparation(_ value: PreparedFormalUnit) throws {
        try ensureAccepting()
        try validatePreparation(value)
        let bytes = try Canonical.encode(value)
        try database.insert("preparation",id: value.id,bytes: bytes)
    }
    private func validatePreparation(_ value: PreparedFormalUnit) throws {
        let key = try PreparedFormalUnit.key(sourceDigest: value.sourceDigest,language: value.language,executorIdentity: value.executorIdentity)
        guard key == value.id else { throw InvarError("INPUT_MISMATCH","Prepared unit cache key differs") }
        let directory = try preparationOutput(value.id)
        let manifest = try bounded(directory.appendingPathComponent("compilation.json"),maximum: 32768)
        let source = try bounded(directory.appendingPathComponent("source.txt"),maximum: 1_000_000)
        guard Canonical.digest(manifest) == value.manifest.sha256, value.manifest.byteCount == manifest.count, Canonical.digest(source) == value.sourceDigest else { throw InvarError("STORE_INTEGRITY","Prepared compilation manifest/source changed") }
    }
    public func savePlan(_ plan: VerificationPlan) throws {
        try ensureAccepting()
        try PlanValidation.validate(plan)
        if let policy = try loadPolicy() { guard policy.workspaceID == plan.body.input.workspaceID, policy.engineIdentity == plan.body.executorIdentity else { throw InvarError("INPUT_MISMATCH","Plan differs from the host workspace/engine") } }
        _ = try inputRoot(plan.body.input.id)
        let inventory = try inventory(plan.body.input)
        try PlanValidation.bind(plan,to: inventory)
        for unit in plan.body.jobs.compactMap(\.compilation) { guard try loadPreparation(unit.id) == unit else { throw InvarError("INPUT_MISMATCH","Plan compilation is not published") } }
        try transaction {
            let bytes = try Canonical.encode(plan)
            try database.insert("plan",id: plan.id,bytes: bytes)
            try publishPlanMetadata(plan)
            try database.link(ownerKind: "plan",ownerID: plan.id,targetKind: "input",targetID: plan.body.input.id)
            for unit in plan.body.jobs.compactMap(\.compilation) { try database.link(ownerKind: "plan",ownerID: plan.id,targetKind: "preparation",targetID: unit.id) }
        }
    }
    public func loadPlan(_ id: String) throws -> VerificationPlan {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("plan", id: id) else { throw InvarError("PLAN_NOT_FOUND", "Unknown plan") }
        let value = try JSONDecoder().decode(VerificationPlan.self, from: bytes)
        try PlanValidation.validate(value)
        let input = try inputReference(value.body.input.id)
        guard input == value.body.input else { throw InvarError("STORE_INTEGRITY","Plan input reference differs") }
        for unit in value.body.jobs.compactMap(\.compilation) {
            guard let bytes = try database.load("preparation",id: unit.id) else { throw InvarError("STORE_INTEGRITY","Missing prepared compilation") }
            let retained = try JSONDecoder().decode(PreparedFormalUnit.self,from: bytes)
            guard retained == unit else { throw InvarError("STORE_INTEGRITY","Prepared compilation record differs") }
        }
        guard value.id == id else { throw InvarError("INVALID_PLAN", "Stored plan identity differs") }
        return value
    }
    public func outputRoot(for id: String) throws -> URL { try ensureAccepting(); try safeID(id); return root.appendingPathComponent("runs/" + id) }
    public func adoptArtifacts(_ evidence: VerificationEvidence,from output: URL,maximumBytes: Int) throws {
        try ensureAccepting()
        try database.ensureOpen()
        var total = 0
        for reference in evidence.artifacts {
            guard reference.byteCount >= 0, reference.byteCount <= maximumBytes - total else { throw InvarError("RESOURCE_LIMIT","Artifact adoption exceeds reserved attempt bytes",exitCode: 6) }; total += reference.byteCount
            let source = output.appendingPathComponent("artifacts/" + reference.id)
            let file = source.appendingPathComponent(artifactName(reference))
            try verifyArtifact(reference,file: file)
            let destination = root.appendingPathComponent("artifacts/" + reference.id)
            let existed = FileManager.default.fileExists(atPath: destination.path)
            if existed { _ = try artifactRoot(reference) }
            else {
                if reference.mediaType == "application/vnd.formal.evidence.sqlite" {
                    struct Manifest: Decodable { let id: String; let sha256: String; let byteCount: Int }
                    let bytes = try bounded(source.appendingPathComponent("manifest.json"),maximum: 4096)
                    let manifest = try JSONDecoder().decode(Manifest.self,from: bytes)
                    guard manifest.id == reference.id, manifest.sha256 == reference.sha256, manifest.byteCount == reference.byteCount else { throw InvarError("INVALID_RESULT","Formal bundle manifest differs") }
                }
                try synchronizeDirectory(source)
                try FileManager.default.moveItem(at: source,to: destination)
                try synchronizeDirectory(destination.deletingLastPathComponent())
            }
            let bytes = try Canonical.encode(reference)
            try transaction {
                try database.insert("artifact",id: reference.id,bytes: bytes)
                if !existed { try transferOwnership(from: output,relativeRoot: "artifacts/" + reference.id,objectKind: "artifact",objectID: reference.id) }
            }
        }
    }
    public func artifactRoot(_ reference: EvidenceArtifactReference) throws -> URL {
        try ensureAccepting()
        try database.ensureOpen(); try safeID(reference.id)
        let directory = root.appendingPathComponent("artifacts/" + reference.id)
        try verifyArtifact(reference,file: directory.appendingPathComponent(artifactName(reference)))
        return directory
    }
    private func artifactName(_ reference: EvidenceArtifactReference) -> String {
        reference.mediaType == "application/vnd.formal.evidence.sqlite" ? "evidence.sqlite" : "blob"
    }
    private func verifyArtifact(_ reference: EvidenceArtifactReference,file: URL) throws {
        try safeID(reference.id)
        guard reference.id == reference.sha256, reference.byteCount >= 0, file.resolvingSymlinksInPath().path == file.standardizedFileURL.path else { throw InvarError("INVALID_RESULT","Unsafe artifact reference/path") }
        let handle = try FileHandle(forReadingFrom: file)
        do {
            var total = 0, digest = SHA256()
            while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                guard chunk.count <= reference.byteCount - total else { throw InvarError("STORE_INTEGRITY","Artifact exceeds declared bytes") }
                digest.update(data: chunk); total += chunk.count
            }
            try handle.close()
            let sha = digest.finalize().map { String(format: "%02x",$0) }.joined()
            guard total == reference.byteCount, sha == reference.sha256 else { throw InvarError("STORE_INTEGRITY","Artifact digest/size mismatch") }
        } catch {
            do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Artifact audit failed (\(error)); close failed (\(cleanup))") }
            throw error
        }
    }
    public func saveRun(_ run: VerificationRun) throws {
        try ensureAccepting()
        try validateRun(run); try safeID(run.id)
        try transaction {
            for value in run.attempts { try saveEvidence(value) }
            for value in run.associations { try saveAssociation(value) }
            let bytes = try Canonical.encode(run)
            try database.insert("run",id: run.id,bytes: bytes)
            try database.link(ownerKind: "run",ownerID: run.id,targetKind: "plan",targetID: run.planID)
            for evidence in run.attempts { try database.link(ownerKind: "run",ownerID: run.id,targetKind: "evidence",targetID: evidence.id) }
            for association in run.associations { try database.link(ownerKind: "run",ownerID: run.id,targetKind: "association",targetID: association.id) }
        }
    }
    public func loadRun(_ id: String) throws -> VerificationRun {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("run", id: id) else { throw InvarError("RUN_NOT_FOUND", "Unknown verification run") }
        let result = try JSONDecoder().decode(VerificationRun.self, from: bytes)
        guard result.id == id else { throw InvarError("STORE_INTEGRITY", "Run identity differs") }
        try validateRun(result)
        for evidence in result.attempts { guard try database.load("evidence",id: evidence.id) == Canonical.encode(evidence) else { throw InvarError("STORE_INTEGRITY","Run evidence reference differs from retained record") } }
        for association in result.associations { guard try database.load("association",id: association.id) == Canonical.encode(association) else { throw InvarError("STORE_INTEGRITY","Run association reference differs from retained record") } }
        return result
    }
    private func validateRun(_ run: VerificationRun) throws {
        let plan = try schedulingPlan(run.planID)
        guard run.attempts.count == plan.jobs.count, Set(run.attempts.map(\.jobID)).count == run.attempts.count else { throw InvarError("INVALID_RESULT", "Run lost or duplicated obligations") }
        for attempt in run.attempts { guard let job = plan.jobs.first(where: { $0.id == attempt.jobID }) else { throw InvarError("INVALID_RESULT", "Unknown result job") }; try PlanValidation.evidence(attempt, job: job) }
        guard run.associations.count == run.attempts.count, Set(run.associations.map(\.evidenceID)) == Set(run.attempts.map(\.id)) else { throw InvarError("INVALID_RESULT","Missing or duplicated evidence associations") }
        for evidence in run.attempts {
            if evidence.inputID != plan.input.id {
                guard let job = plan.jobs.first(where: { $0.id == evidence.jobID }) else { throw InvarError("INVALID_RESULT","Unknown evidence job") }
                guard let key = job.executionKey, key == evidence.executionKey, run.associations.contains(where: { $0.evidenceID == evidence.id && $0.targetDescriptorID == job.descriptorID }) else { throw InvarError("INVALID_RESULT","Evidence scope differs from target plan") }
            }
            for artifact in evidence.artifacts { _ = try artifactRoot(artifact) }
        }
        for value in run.associations {
            guard let evidence = run.attempts.first(where: { $0.id == value.evidenceID }), value.input.workspaceID == plan.input.workspaceID,
                ["matchesInputs","stale","unknown","unmatched"].contains(value.applicability),
                value.applicability != "matchesInputs" || value.input.semanticDigest == plan.input.semanticDigest else { throw InvarError("INVALID_RESULT","Invalid applicability target or status") }
            let expected = EvidenceAssociation.make(evidence: evidence,targetDescriptorID: value.targetDescriptorID,changeRevisionID: value.changeRevisionID,input: value.input,status: value.applicability,basis: value.basis,unknownBoundaries: value.unknownBoundaries,reuseDecision: value.reuseDecision)
            guard expected == value else { throw InvarError("INVALID_RESULT","Association identity differs") }
        }
        guard RunAssessment.accepts(run.attempts, associations: run.associations, plan: plan) == run.accepted else { throw InvarError("INVALID_RESULT", "Aggregate result disagrees with evidence") }
    }
    public func saveReplay(originalRunID: String, replayRunID: String) throws {
        try ensureAccepting()
        let original = try loadRun(originalRunID), replay = try loadRun(replayRunID)
        let comparison = try ReplayComparison(original: original, replay: replay)
        let bytes = try Canonical.encode(comparison)
        try database.insert("replay", id: replayRunID, bytes: bytes)
    }
    public func loadReplay(_ replayRunID: String) throws -> ReplayComparison? {
        try ensureAccepting()
        try safeID(replayRunID)
        guard let bytes = try database.load("replay", id: replayRunID) else { return nil }
        let comparison = try JSONDecoder().decode(ReplayComparison.self, from: bytes)
        let original = try loadRun(comparison.originalRunID), replay = try loadRun(replayRunID)
        guard try ReplayComparison(original: original, replay: replay) == comparison else { throw InvarError("STORE_INTEGRITY", "Replay association differs from retained evidence") }
        return comparison
    }

    public func shutdown() async throws {
        if let shutdownTask { try await shutdownTask.value; return }
        closing = true
        let reads = Array(diskReads.values)
        let task = Task {
            for read in reads { read.cancel() }
            for read in reads {
                do { _ = try await read.value } catch is CancellationError {} catch { throw InvarError("CLEANUP_FAILED","Store disk reader failed during shutdown: \(error)") }
            }
            if inputWrites > 0 { await withCheckedContinuation { inputWriteWaiters.append($0) } }
            let checkpoint = try database.scalar("PRAGMA wal_checkpoint(TRUNCATE)")
            guard checkpoint == 0 else { throw InvarError("STORE_CLOSE_FAILED","WAL checkpoint is still busy") }
            try database.close()
        }
        shutdownTask = task
        try await task.value
    }
    func ensureAccepting() throws {
        guard !closing else { throw InvarError("STORE_CLOSED","Store is draining or closed") }
        try database.ensureOpen()
    }
    func safeID(_ id: String) throws { try PlanValidation.identifier(id) }
    func durableWrite(_ bytes: Data, to path: URL) throws {
        try bytes.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        let handle = try FileHandle(forWritingTo: path)
        do { try handle.synchronize(); try handle.close() }
        catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED", "Sync failed (\(error)); close failed (\(cleanup))") }; throw error }
    }
    func synchronizeDirectory(_ path: URL) throws {
        let descriptor = open(path.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InvarError("STORE_SYNC_FAILED", "Cannot open content directory") }
        let result = fsync(descriptor), closeResult = Darwin.close(descriptor)
        guard result == 0, closeResult == 0 else { throw InvarError("STORE_SYNC_FAILED", "Cannot synchronize content directory") }
    }
    func bounded(_ path: URL, maximum: Int) throws -> Data {
        guard path.resolvingSymlinksInPath().path == path.standardizedFileURL.path else { throw InvarError("UNSAFE_STORE", "Content path contains a symlink", exitCode: 8) }
        let values = try path.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximum else { throw InvarError("INVALID_INPUT", "Expected a bounded regular file") }
        let handle = try FileHandle(forReadingFrom: path)
        do {
            let bytes = try handle.read(upToCount: maximum + 1) ?? Data()
            try handle.close()
            guard bytes.count <= maximum else { throw InvarError("RESOURCE_LIMIT", "File grew beyond its budget", exitCode: 6) }
            return bytes
        } catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED", "Read failed (\(error)); close failed (\(cleanup))") }; throw error }
    }
}
