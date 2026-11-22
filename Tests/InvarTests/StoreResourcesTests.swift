import Foundation
import Testing
import VerificationCore
import VerificationStore
import VerificationDiscovery

@Suite(.timeLimit(.minutes(1)))
struct StoreResourcesTests {
    let policy = StorePolicy(maximumRetainedBytes: 8_388_608,maximumDatabaseBytes: 1_048_576,failureReserveBytes: 65_536,maximumRecords: 1000,maximumFiles: 1000,maximumReservations: 4,retentionSeconds: 0.001)
    @Test func storageReservationsIncludeRetainedBytesAndDetectOwnedScratchOverflow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        let first = StorageReservation(id: "first",relativeRoot: "runs/first",maximumBytes: 4_194_304,maximumFiles: 100)
        try await store.reserve(first); try await store.reserve(first)
        let second = StorageReservation(id: "second",relativeRoot: "runs/second",maximumBytes: 4_194_304,maximumFiles: 100)
        await #expect(throws: InvarError.self) { try await store.reserve(second) }
        let usage = try await store.usage()
        #expect(usage.reservationCount == 1 && usage.reservedBytes == first.maximumBytes && usage.databaseBytes > 0)
        let work = root.appendingPathComponent(first.relativeRoot)
        try FileManager.default.createDirectory(at: work,withIntermediateDirectories: true)
        try Data(repeating: 1,count: first.maximumBytes+1).write(to: work.appendingPathComponent("overflow"))
        await #expect(throws: InvarError.self) { try await store.usage() }
        try FileManager.default.removeItem(at: work)
        try await store.releaseReservation(first.id)
        try await store.reserve(second)
        try await store.releaseReservation(second.id)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func pinnedArtifactSurvivesPruningAndReleasedArtifactRetiresWithoutDanglingEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        let inventory = DomainTests.inventory()
        let inputID = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
        let bytes = Data("{\"observed\":true}".utf8), digest = Canonical.digest(bytes)
        let reference = EvidenceArtifactReference(id: digest,sha256: digest,byteCount: bytes.count,mediaType: "application/json",profile: "fixture/1")
        let producer = root.appendingPathComponent("producer"), directory = producer.appendingPathComponent("artifacts/" + digest)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        try bytes.write(to: directory.appendingPathComponent("blob"))
        let evidence = VerificationEvidence(inputID: inputID,jobID: "a",execution: "completed",outcome: "holdsWithinScope",domain: "architecture",translation: "notApplicable",scope: "fixture",adequacy: "completeWithinScope",detail: "Fixture storage only",artifacts: [reference],startedAt: "now",finishedAt: "now")
        await #expect(throws: (any Error).self) { try await store.saveEvidence(evidence) }
        try await store.adoptArtifacts(evidence,from: producer,maximumBytes: 1_048_576)
        try await store.saveEvidence(evidence)
        let pin = RetentionPin(id: "reader-pin",ownerKind: "query",ownerID: "reader",objectKind: "evidence",objectID: evidence.id,expiresAt: nil)
        try await store.pin(pin)
        let now = Date().timeIntervalSince1970 + 2
        _ = try await store.prune(now: now,maximumObjects: 100)
        #expect(try await store.loadEvidence(evidence.id) == evidence)
        _ = try await store.artifactRoot(reference)
        try await store.releasePin(pin.id)
        let removed = try await store.prune(now: now+2,maximumObjects: 100)
        #expect(removed.removedObjects.contains("evidence:" + evidence.id))
        await #expect(throws: InvarError.self) { try await store.loadEvidence(evidence.id) }
        await #expect(throws: (any Error).self) { try await store.artifactRoot(reference) }
        try await store.recoverRetiredObjects()
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func registeredBaselineSealIsImmutableAndConflictingRepeatIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root)
        let helper = ChangeTrackingTests(), before = helper.capture(["Source.swift":Data("let value = 1".utf8)],snapshot: "before"), after = helper.capture(["Source.swift":Data("let value = 2".utf8)],snapshot: "after")
        _ = try await store.saveInput(before); _ = try await store.saveInput(after)
        let old = try VerificationInput.reference(before.inventory), new = try VerificationInput.reference(after.inventory)
        let claim = ChangeClaim(intent: "Update value",paths: ["Source.swift"],entityIDs: [],patchDigest: nil,expectedFiles: [])
        let record = ChangeRecord(id: "change",workspaceID: old.workspaceID,ownerPrincipal: "fixture",sessionID: nil,baseline: old,claim: claim,state: "open",revision: 1,sealedRevisionID: nil)
        try await store.createChange(record); try await store.createChange(record)
        let analysis = try ExactChangeAnalyzer().analyze(helper.request(before,after,claim: claim))
        let revision = try ChangeRevision.make(changeID: record.id,parentID: nil,before: old,after: new,analysis: analysis)
        let sealed = try await store.sealChange(revision,expectedRevision: 1)
        #expect(sealed.state == "sealed" && sealed.revision == 2)
        #expect(try await store.sealChange(revision,expectedRevision: 1) == sealed)
        let forged = ChangeRevision(id: revision.id,changeID: revision.changeID,parentID: nil,before: old,after: new,delta: revision.delta,correspondences: revision.correspondences,attribution: revision.attribution,impactEntityIDs: [],impactComplete: true,diagnostics: ["forged"])
        await #expect(throws: InvarError.self) { try await store.sealChange(forged,expectedRevision: 1) }
        #expect(try await store.loadChangeRevision(revision.id) == revision)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension StoreResourcesTests {
    @Test func artifactPublicationTransfersItsExistingReservationCharge() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        let inventory = DomainTests.inventory()
        let inputID = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
        let reservation = StorageReservation(id: "execution",relativeRoot: "runs/execution",maximumBytes: 262_144,maximumFiles: 64)
        try await store.reserve(reservation)
        let output = try await store.outputRoot(for: reservation.id), bytes = Data(repeating: 65,count: 65_536)
        let hash = Canonical.digest(bytes)
        let reference = EvidenceArtifactReference(id: hash,sha256: hash,byteCount: bytes.count,mediaType: "application/json",profile: "fixture/1")
        let directory = output.appendingPathComponent("artifacts/" + hash)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        try bytes.write(to: directory.appendingPathComponent("blob"))
        let evidence = VerificationEvidence(inputID: inputID,jobID: "a",execution: "completed",outcome: "holdsWithinScope",domain: "architecture",translation: "notApplicable",scope: "fixture",detail: "Storage transfer fixture",artifacts: [reference],startedAt: "now",finishedAt: "now")
        let before = try await store.usage()
        #expect(before.reservedBytes == reservation.maximumBytes - bytes.count)
        try await store.adoptArtifacts(evidence,from: output,maximumBytes: reservation.maximumBytes)
        let after = try await store.usage()
        #expect(after.reservedBytes == before.reservedBytes)
        _ = try await store.prune(now: Date().timeIntervalSince1970 + 2,maximumObjects: 100)
        _ = try await store.artifactRoot(reference)
        try await store.releaseReservation(reservation.id)
        #expect(try await store.usage().reservedBytes == 0)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension StoreResourcesTests {
    @Test func captureQuotaIsRefusedBeforeAnyInputIsPublished() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        let bytes = Data(repeating: 65,count: 4_194_304), digest = Canonical.digest(bytes)
        let entries = [InputEntry(path: "A.swift",digest: digest,byteCount: bytes.count),InputEntry(path: "B.swift",digest: digest,byteCount: bytes.count)]
        let inventory = ScopeInventory(workspaceID: "workspace",snapshotID: "snapshot",contextDigest: "context",metadata: [:],entities: [],facts: [],coverage: [],inputs: entries)
        let capture = CapturedWorkspace(inventory: inventory,files: ["A.swift":bytes,"B.swift":bytes])
        await #expect(throws: InvarError.self) { try await store.saveInput(capture) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("inputs").path).isEmpty)
        #expect(try await store.usage().reservationCount == 0)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension StoreResourcesTests {
    @Test func admissionRetainsDatabaseAndWALGrowthHeadroom() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        let reservation = StorageReservation(id: "too-large",relativeRoot: "runs/too-large",maximumBytes: 6_291_456,maximumFiles: 64)
        await #expect(throws: InvarError.self) { try await store.reserve(reservation) }
        try await store.releaseReservation(reservation.id)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension StoreResourcesTests {
    @Test func startupRetiresAbandonedCaptureAndPreparationCapacityWithoutDeletingCommittedTransfers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        let capture = CapturedWorkspace(inventory: DomainTests.inventory(),files: [:])
        let inputID = try await store.saveInput(capture)
        let reservation = StorageReservation(id: "interrupted-preparation",relativeRoot: "runs/interrupted-preparation",maximumBytes: 1_048_576,maximumFiles: 100)
        try await store.reserve(reservation)
        let scratch = root.appendingPathComponent(reservation.relativeRoot)
        try FileManager.default.createDirectory(at: scratch,withIntermediateDirectories: true)
        try Data("unfinished".utf8).write(to: scratch.appendingPathComponent("partial"))
        let artifactBytes = Data(repeating: 65,count: 65536), hash = Canonical.digest(Data(repeating: 65,count: 65536))
        let artifact = EvidenceArtifactReference(id: hash,sha256: hash,byteCount: artifactBytes.count,mediaType: "application/json",profile: "fixture/1")
        let staged = scratch.appendingPathComponent("artifacts/" + hash)
        try FileManager.default.createDirectory(at: staged,withIntermediateDirectories: true)
        try artifactBytes.write(to: staged.appendingPathComponent("blob"))
        let evidence = VerificationEvidence(inputID: inputID,jobID: "a",execution: "completed",outcome: "holdsWithinScope",domain: "architecture",translation: "notApplicable",scope: "fixture",detail: "Committed transfer before controller loss",artifacts: [artifact],startedAt: "now",finishedAt: "now")
        try await store.adoptArtifacts(evidence,from: scratch,maximumBytes: reservation.maximumBytes)
        try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root,policy: policy)
        #expect(try await reopened.usage().reservationCount == 1)
        try await reopened.discardAbandonedReservation(reservation.id)
        try await reopened.discardAbandonedReservation(reservation.id)
        #expect(try await reopened.usage().reservationCount == 0)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
        let reference = try await reopened.inputReference(inputID)
        #expect(try await reopened.capture(reference) == capture)
        let retainedArtifact = try await reopened.artifactRoot(artifact)
        #expect(try Data(contentsOf: retainedArtifact.appendingPathComponent("blob")) == artifactBytes)
        try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension StoreResourcesTests {
    @Test func cancellationAndEpochRecoveryRemainPossibleWhenOrdinaryRecordAdmissionIsFull() async throws {
        let quota = StorePolicy(maximumRetainedBytes: 8_388_608,maximumDatabaseBytes: 1_048_576,failureReserveBytes: 65_536,maximumRecords: 64,maximumFiles: 1000,maximumReservations: 1,retentionSeconds: 3600)
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")],policy: quota)
        defer { do { try await store.shutdown(); try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let epoch = UUID().uuidString, engine = String(repeating: "1",count: 64)
        try await store.activateEpoch(epoch,engineIdentity: engine)
        let (envelope,operation) = try await DurableCoordinatorTests().request(store: store,plan: plan,epoch: epoch,key: "cancel-at-quota")
        let demand = RunDemand(id: UUID().uuidString,envelopeID: envelope.id,principal: envelope.principal,origin: "internal",request: operation,planID: plan.id,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        _ = try await store.acceptDemand(envelope,demand: demand,now: Date().timeIntervalSince1970)
        var full = false
        for _ in 0..<128 {
            do { try await store.saveEvidence(VerificationEvidence(inputID: plan.body.input.id,jobID: UUID().uuidString,execution: "completed",outcome: "unknown",domain: "architecture",translation: "notApplicable",scope: "Quota fixture",detail: "Fill ordinary record capacity",startedAt: "fixture",finishedAt: "fixture")) }
            catch let error as InvarError where error.code == "STORE_QUOTA" { full = true; break }
        }
        #expect(full)
        _ = try await store.beginDemandCancellation(demand.id,principal: demand.principal,administrative: false)
        let terminal = try await store.finishDemandFailure(demand.id,failure: InvarError("CANCELLED","Cancelled under pressure"),cancelled: true)
        #expect(terminal.state == "cancelled")
        try await store.activateEpoch(UUID().uuidString,engineIdentity: engine)
        #expect(try await store.loadDemand(demand.id) == terminal)
    }
}

extension StoreResourcesTests {
    @Test func abandonedReservationInspectionRefusesSymlinkAndUnknownRootsBeforePhysicalRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        defer { do { try await store.shutdown(); try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: outside) } catch { Issue.record(error) } }
        try FileManager.default.createDirectory(at: outside,withIntermediateDirectories: true)
        try Data("retained".utf8).write(to: outside.appendingPathComponent("sentinel"))
        let reservation = StorageReservation(id: "alias",relativeRoot: "runs/alias",maximumBytes: 1024,maximumFiles: 10)
        try await store.reserve(reservation)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("runs/alias"),withDestinationURL: outside)
        await #expect(throws: InvarError.self) { try await store.abandonedReservationRoot("alias") }
        await #expect(throws: InvarError.self) { try await store.discardAbandonedReservation("alias") }
        #expect(try Data(contentsOf: outside.appendingPathComponent("sentinel")) == Data("retained".utf8))
        #expect(try await store.storageReservations() == [reservation])
    }
}
