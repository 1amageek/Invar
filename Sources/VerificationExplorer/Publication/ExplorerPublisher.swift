import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import FormalEvidence
import Foundation
import VerificationCore

/// Owns durable delivery of committed truth; it does not decide verification outcomes.
public actor ExplorerPublisher: VerificationPublishing {
    private let repository: any VerificationRepository
    private let manifest: ExtensionManifest
    private let transport: @Sendable () async throws -> any ArchitectureExtensionProviding
    private let resources: any WorkspaceResourceAdmitting
    private var pump: Task<Void,Never>?
    private var stopped = false
    private var flushing = false
    private var failure: InvarError?
    public init(repository: any VerificationRepository,manifest: ExtensionManifest,resources: any WorkspaceResourceAdmitting,transport: @escaping @Sendable () async throws -> any ArchitectureExtensionProviding) {
        self.repository = repository; self.manifest = manifest; self.resources = resources; self.transport = transport
    }
    public func start() async throws {
        guard !stopped, pump == nil else { throw InvarError("INVALID_TRANSITION","Publisher already started or stopped") }
        for id in try await repository.pendingPublicationIDs() {
            guard let record = try await repository.loadPublication(id), record.state != "ready" else { continue }
            let blocked = record.revising(state: "blocked",failure: InvarError("INTERRUPTED","Prior reservation has no committed result; no work is restarted",exitCode: 6))
            try await repository.savePublication(blocked,expectedRevision: record.revision)
        }
        pump = Task {
            while !Task.isCancelled {
                do { try await self.flush(); try await Task.sleep(for: .seconds(3)) }
                catch is CancellationError { return }
                catch { self.failure = Self.error(error); do { try await Task.sleep(for: .seconds(3)) } catch { return } }
            }
        }
    }
    public func diagnostic() -> InvarError? { failure }
    private static func error(_ error: any Error) -> InvarError {
        let code: String, message: String, exit: Int32
        if let value = error as? ArchitectureError { code = value.code; message = value.message; exit = value.exitCode }
        else if let value = error as? InvarError { code = value.code; message = value.message; exit = value.exitCode }
        else { code = "PUBLICATION_FAILED"; message = String(describing: error); exit = 7 }
        return InvarError(String(code.prefix(128)),String(message.prefix(512)),exitCode: exit)
    }
    private func binding(_ input: VerificationInput, node: VerificationNode?) async throws -> ExtensionBinding {
        let inventory = try await repository.inventory(input)
        guard let records = inventory.originalRecords["inputManifest"], records.count == 1 else { throw InvarError("INPUT_MISMATCH","Original owner manifest is unavailable") }
        let original = try JSONDecoder().decode(InputManifest.self,from: records[0]), digest = try original.digest
        guard original.workspaceID == input.workspaceID, original.snapshotID == input.snapshotID else { throw InvarError("INPUT_MISMATCH","Original owner manifest differs from sealed input") }
        return ExtensionBinding(workspaceID: input.workspaceID,snapshotID: input.snapshotID,inputManifestDigest: digest,entityIDs: node.map { [$0.entityID] } ?? [])
    }
    public func reserve(demand: RunDemand,plan: SchedulingPlan) async throws {
        guard !stopped else { throw InvarError("PUBLICATION_CLOSED","Publisher is stopped") }
        if let previous = try await repository.loadPublication(demand.id) {
            guard previous.input == plan.input, previous.state == "reserved" || previous.state == "blocked" else { throw InvarError("INVALID_TRANSITION","Publication has already left reservation") }; return
        }
        let resourceID = "publication-reserve-" + demand.id
        try await resources.acquire(ResourceRequest(id: resourceID,memoryMiB: 256,processes: 0,scratchBytes: 0,priority: 0))
        defer { await resources.release(resourceID) }
        let sourceBinding = try await binding(plan.input,node: demand.request.verificationNode)
        let external = demand.origin == "provider" ? try await repository.providerActionForDemand(demand.id) : nil
        guard demand.origin != "provider" || external != nil else { throw InvarError("ACTION_NOT_FOUND","Provider publication lost its original preflight") }
        let record = PublicationRecord(id: demand.id,runRequestID: external?.runRequestID,entityID: demand.request.verificationNode?.entityID,providerID: manifest.extensionID,input: plan.input,bindingDigest: sourceBinding.inputManifestDigest)
        try await repository.savePublication(record,expectedRevision: 0)
        let next: PublicationRecord
        do {
            let provider = try await transport()
            if let external {
                let original = try JSONDecoder().decode(ExtensionRun.self,from: external.run)
                guard let checking = provider as? any OriginalPublicationChecking else { throw InvarError("UNSUPPORTED_CAPABILITY","Cannot verify Provider preflight run") }
                try await checking.requireOriginalRun(original)
            }
            let run = try await provider.begin(runID: record.runRequestID,scope: sourceBinding.entityIDs.first ?? "workspace",contributionSetID: "verification",binding: sourceBinding,kinds: sourceBinding.entityIDs.isEmpty ? ["graph"] : ["annotation","graph"],viewIDs: [])
            if let external {
                let original = try JSONDecoder().decode(ExtensionRun.self,from: external.run)
                guard run.id == original.id, run.slot == original.slot, run.generation == original.generation else { throw InvarError("IDEMPOTENCY_CONFLICT","Provider publication changed its original reservation") }
            }
            let handle = try CanonicalJSON.encode(run)
            guard !run.committed, run.completion == "pending", run.providerID == record.providerID, run.binding == sourceBinding else { throw InvarError("INVALID_PUBLICATION","Reservation is not new pending result work") }
            next = record.revising(state: "reserved",slot: run.slot,generation: run.generation,handle: handle)
        } catch {
            next = record.revising(state: "blocked",failure: Self.error(error))
        }
        // Persistence failure is not rounded into a successful reservation.
        try await repository.savePublication(next,expectedRevision: record.revision)
    }
    public func prepare(demand: RunDemand,run: VerificationRun,view: ChangeVerificationView) async throws -> PublicationRecord {
        guard let record = try await repository.loadPublication(demand.id) else { throw InvarError("INVALID_PUBLICATION","Result work lacked a prior publication attempt") }
        let reference = try view.reference()
        if record.state == "blocked" { return record.revising(state: "blocked",view: reference,failure: record.failure) }
        guard record.state == "reserved" else { throw InvarError("INVALID_TRANSITION","Outbox already prepared") }
        let resourceID = "publication-" + demand.id
        do {
            try await resources.acquire(ResourceRequest(id: resourceID,memoryMiB: 256,processes: 0,scratchBytes: 0,priority: 0))
            defer { await resources.release(resourceID) }
            guard view.input == record.input else { throw InvarError("INPUT_CHANGED","Result's current-input association differs from its original publication reservation") }
            let sourceBinding = try await binding(record.input,node: demand.request.verificationNode)
            guard sourceBinding.inputManifestDigest == record.bindingDigest else { throw InvarError("INPUT_MISMATCH","Original publication manifest changed") }
            let contributions = try await contributions(run: run,view: view,binding: sourceBinding)
            let bytes = try CanonicalJSON.encode(contributions)
            guard bytes.count <= 2 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT","Complete projection exceeds publication budget",exitCode: 6) }
            let completion = !run.attempts.isEmpty && run.attempts.allSatisfy { $0.execution == "completed" } ? "complete" : "partial"
            return record.revising(state: "ready",view: reference,payload: bytes,completion: completion)
        } catch is CancellationError { throw CancellationError() }
        catch { return record.revising(state: "blocked",view: reference,failure: Self.error(error)) }
    }
    private func contributions(run: VerificationRun,view: ChangeVerificationView,binding: ExtensionBinding) async throws -> [ExtensionContribution] {
        let reference = try view.reference()
        var graphs: [ExtensionContribution] = [], totalGraphs = 0, selectedRoots: [JSONValue] = []
        let budget = EvidenceReadBudget(maximumDatabaseBytes: 536870912,maximumRecordBytes: 262144,maximumPageBytes: 262144,maximumNodes: 96,maximumEdges: 192,maximumTraversalNodes: 4096,maximumCursors: 1)
        var checkedPlan: VerificationPlan?, captured: CapturedWorkspace?
        var sourceBindings: [String: JSONValue] = [:]
        var conditionsByEvidence: [String: [JSONValue]] = [:]
        for evidence in run.attempts {
            for artifact in evidence.artifacts where artifact.profile == "project-report/1" {
                let root = try await repository.artifactRoot(artifact)
                let bytes = try Data(contentsOf: root.appendingPathComponent("blob"),options: .mappedIfSafe)
                guard bytes.count == artifact.byteCount, Canonical.digest(bytes) == artifact.sha256 else { throw InvarError("INPUT_MISMATCH","Project report artifact differs from its retained digest") }
                _ = try ProjectReportAssessment.outcome(bytes)
                var report = try JSONDecoder().decode(JSONValue.self,from: bytes).object
                let prefix = manifest.extensionID + ":project-" + evidence.id + ":"
                report["nodes"] = .array((report["nodes"]?.array ?? []).map { node in
                    var n = node.object; n["id"] = .string(prefix + (node["id"].string ?? ""))
                    if let parent = node["parentID"].string { n["parentID"] = .string(prefix + parent) }; return .object(n)
                })
                report["edges"] = .array((report["edges"]?.array ?? []).map { edge in
                    var e = edge.object
                    for key in ["id","source","target"] { e[key] = .string(prefix + (edge[key].string ?? "")) }; return .object(e)
                })
                var metadata = report["metadata"]?.object ?? [:], assessment = metadata["verificationReport"]?.object ?? [:]
                assessment["requirements"] = .array((assessment["requirements"]?.array ?? []).map { row in
                    var r = row.object; r["nodeID"] = .string(prefix + (row["nodeID"].string ?? "")); return .object(r)
                })
                var workflow = assessment["workflow"]?.object ?? [:]
                workflow["stages"] = .array((workflow["stages"]?.array ?? []).map { stage in
                    var value = stage.object; value["nodeID"] = .string(prefix + (stage["nodeID"].string ?? "")); return .object(value)
                })
                assessment["workflow"] = .object(workflow)
                assessment["mapBinding"] = .object(["workspaceID":.string(binding.workspaceID),"snapshotID":.string(binding.snapshotID),"entityID":.string(binding.entityIDs.first ?? "")])
                metadata["verificationReport"] = .object(assessment); report["metadata"] = .object(metadata)
                let graph = ExtensionContribution(id: manifest.extensionID + ":project-report-" + evidence.id,kind: "graph",binding: binding,data: .object(report))
                try ExtensionRules.contribution(graph,provider: manifest,binding: binding); graphs.append(graph); totalGraphs += 1
            }
            for artifact in evidence.artifacts where artifact.mediaType == "application/vnd.formal.evidence.sqlite" && artifact.profile == "formal-evidence/1" {
                let root = try await repository.artifactRoot(artifact)
                let bundle = EvidenceBundleReference(id: artifact.id,sha256: artifact.sha256,byteCount: artifact.byteCount)
                let reader = try EvidenceBundleReader(root: root.deletingLastPathComponent(),reference: bundle,budget: budget)
                do {
                let catalog = try await reader.catalog()
                let context = try FormalProjectionContext(providerID: manifest.extensionID,view: view,evidence: evidence,bundle: artifact,binding: binding)
                if !binding.entityIDs.isEmpty {
                    for claim in catalog.claims {
                        if var condition = try VerifiedCondition.record(claim, bundleID: artifact.id) {
                            if claim.domain == "generatedModel.lean.quantified", let entry = condition["entry"].string {
                                if checkedPlan == nil { checkedPlan = try await repository.loadPlan(run.planID) }
                                if let job = checkedPlan?.body.jobs.first(where: { $0.id == evidence.jobID }),
                                   let prepared = job.compilation, prepared.language == "swift",
                                   claim.artifactDigests.contains(prepared.manifest.sha256), let source = job.formal?.source {
                                    let key = Canonical.parts("swift-call-bindings", [source, prepared.sourceDigest, entry])
                                    if sourceBindings[key] == nil {
                                        if captured == nil { captured = try await repository.capture(view.input) }
                                        if let captured {
                                            sourceBindings[key] = try SwiftCallBindings.resolve(entry: entry, source: source,
                                                digest: prepared.sourceDigest, capture: captured)
                                        }
                                    }
                                    var fields = condition.object
                                    fields["sourceBindings"] = sourceBindings[key]
                                    condition = .object(fields)
                                }
                            }
                            conditionsByEvidence[evidence.id, default: []].append(condition)
                        }
                    }
                }
                for descriptor in catalog.graphs {
                    totalGraphs += 1
                    guard graphs.count < 8, descriptor.extraction == "available" else { continue }
                    let roots = Array(descriptor.roots.prefix(8))
                    let query = FormalGraphQuery(graphID: descriptor.id,roots: roots,relations: [],direction: "outgoing",depth: evidence.outcome == "notEvaluated" ? 32 : 0)
                    let page = try await reader.graph(query)
                    let projection = try FormalGraphProjector().project(page,descriptor: descriptor,query: query,context: context)
                    graphs.append(projection.contribution)
                    selectedRoots.append(.object(["graphID":.string(descriptor.id),"declared":.number(Double(descriptor.roots.count)),"selected":.number(Double(roots.count)),"rootSelectionTruncated":.bool(roots.count < descriptor.roots.count)]))
                }
                } catch {
                    let original = error
                    do { try await reader.shutdown() }
                    catch { throw InvarError("CLEANUP_FAILED","Graph query failed (\(original)); reader shutdown failed (\(error))") }
                    throw original
                }
                try await reader.shutdown()
            }
        }
        let summaries = run.attempts.prefix(128).map { evidence -> JSONValue in
            let association = view.associations.first { $0.evidenceID == evidence.id }
            return .object(["id":.string(manifest.extensionID + ":evidence-" + evidence.id),"kind":.string("verificationEvidence"),"label":.string(evidence.jobID.prefix(128).description),"attributes":.object(["evidenceID":.string(evidence.id),"execution":.string(evidence.execution),"outcome":.string(evidence.outcome),"domain":.string(evidence.domain),"translation":.string(evidence.translation),"adequacy":.string(evidence.adequacy),"applicability":association.map { .string($0.applicability) } ?? .null])])
        }
        let data: JSONValue = .object(["nodes":.array(summaries),"edges":.array([]),"metadata":.object(["viewID":.string(reference.id),"viewDigest":.string(reference.sha256),"evidenceCount":.number(Double(run.attempts.count)),"evidenceTruncated":.bool(run.attempts.count > 128),"formalGraphsTotal":.number(Double(totalGraphs)),"formalGraphsShown":.number(Double(graphs.count)),"formalGraphsOmitted":.number(Double(totalGraphs-graphs.count)),"rootSelections":.array(selectedRoots),"upstreamDependencyStatus":.string(view.input.dependencyStatus),"sourceTextIncluded":.bool(false),"stateValuesIncluded":.bool(false)])])
        let summary = ExtensionContribution(id: manifest.extensionID + ":verification",kind: "graph",binding: binding,data: data)
        try ExtensionRules.contribution(summary,provider: manifest,binding: binding)
        var reports: [ExtensionContribution] = []
        if !binding.entityIDs.isEmpty {
            for evidence in run.attempts {
                var attributes: [String: JSONValue] = ["execution": .string(evidence.execution), "detail": .string(evidence.detail), "conditions": .array(conditionsByEvidence[evidence.id] ?? [])]
                if evidence.domain == "projectContract", evidence.execution != "completed" {
                    attributes["attemptDiagnostic"] = .string(String(decoding: evidence.detail.utf8.prefix(1021),as: UTF8.self))
                }
                if evidence.jobID == "generate-model", evidence.execution == "unsupported", evidence.diagnosticCode == "UNSUPPORTED_SOURCE_PROFILE" {
                    // The source frontend diagnostic is public. Worker logs and other errors remain private.
                    attributes["attemptDiagnostic"] = .string(String(decoding: evidence.detail.utf8.prefix(1021), as: UTF8.self))
                }
                let report = ExtensionAnnotation(reportedStatus: evidence.outcome, claim: "Formal Verification · " + evidence.jobID,
                    scope: evidence.domain + " · " + evidence.scope, assumptions: evidence.assumptions,
                    evidence: [.string(evidence.id)], translationStatus: evidence.translation,
                    attributes: attributes)
                let data = try JSONDecoder().decode(JSONValue.self, from: CanonicalJSON.encode(report))
                let contribution = ExtensionContribution(id: manifest.extensionID + ":report-" + evidence.id, kind: "annotation", binding: binding, data: data)
                try ExtensionRules.contribution(contribution,provider: manifest,binding: binding)
                reports.append(contribution)
            }
        }
        return [summary] + graphs + reports
    }
    public func abandon(demandID: String,failure: InvarError) async throws {
        guard let record = try await repository.loadPublication(demandID), ["reserving","reserved"].contains(record.state) else { return }
        let next = record.revising(state: "blocked",failure: Self.error(failure))
        try await repository.savePublication(next,expectedRevision: record.revision)
    }
    public func flush() async throws {
        guard !flushing, !stopped else { return }
        flushing = true; defer { flushing = false }
        for id in try await repository.pendingPublicationIDs() {
            try Task.checkCancellation()
            let resourceID = "publication-deliver-" + id
            try await resources.acquire(ResourceRequest(id: resourceID,memoryMiB: 256,processes: 0,scratchBytes: 0,priority: 0))
            defer { await resources.release(resourceID) }
            guard let original = try await repository.loadPublication(id), original.state == "ready" else { continue }
            do { try await deliver(original); failure = nil }
            catch is CancellationError { throw CancellationError() }
            catch {
                let error = Self.error(error); failure = error
                guard let current = try await repository.loadPublication(original.id), current.state == "ready" else { continue }
                let terminal = ["ORIGINAL_RUN_LOST","PUBLICATION_SUPERSEDED","PUBLICATION_EXPIRED","IDEMPOTENCY_CONFLICT","INVALID_PUBLICATION","INPUT_CHANGED","POLICY_DENIED","PERMISSION_DENIED"].contains(error.code)
                let state = error.code == "PUBLICATION_SUPERSEDED" ? "superseded" : terminal ? "blocked" : "ready"
                let next = current.revising(state: state,failure: error)
                try await repository.savePublication(next,expectedRevision: current.revision)
            }
        }
    }
    private func deliver(_ original: PublicationRecord) async throws {
        guard let bytes = original.payload, let handle = original.handle, let completion = original.completion else { throw InvarError("INVALID_PUBLICATION","Ready outbox is incomplete") }
        let old = try JSONDecoder().decode(ExtensionRun.self,from: handle)
        let provider = try await transport()
        guard let checking = provider as? any OriginalPublicationChecking else { throw InvarError("UNSUPPORTED_CAPABILITY","Transport cannot prove the original publication still exists") }
        try await checking.requireOriginalRun(old)
        let run = try await provider.begin(runID: original.runRequestID,scope: old.binding.entityIDs.first ?? "workspace",contributionSetID: "verification",binding: old.binding,kinds: old.binding.entityIDs.isEmpty ? ["graph"] : ["annotation","graph"],viewIDs: [])
        guard run.id == old.id, run.providerID == old.providerID, run.slot == old.slot, run.binding == old.binding, run.generation == original.generation else { throw InvarError("IDEMPOTENCY_CONFLICT","Reconnect changed the original reservation generation/input") }
        var current = original
        if !run.committed, run.completion == "pending" {
            let rebound = try CanonicalJSON.encode(run)
            if rebound != handle {
                current = current.revising(state: "ready",handle: rebound)
                try await repository.savePublication(current,expectedRevision: original.revision)
            }
            let contributions = try JSONDecoder().decode([ExtensionContribution].self,from: bytes)
            let diagnostic = contributions.first { $0.kind == "annotation" && $0.data["attributes"]["attemptDiagnostic"].string != nil }
            let manifest = try PublicationManifest(contributions: contributions, attemptDiagnostic: diagnostic?.data["attributes"]["attemptDiagnostic"].string)
            try await provider.prepare(run,manifest: manifest)
            try await provider.stage(run,contributions: contributions)
            try await provider.commit(run,manifest: manifest,completion: completion)
        } else {
            guard run.completion == completion, run.committed == (completion == "complete") else { throw InvarError("IDEMPOTENCY_CONFLICT","Original host completion differs from committed outbox") }
        }
        let terminal = current.revising(state: completion == "complete" ? "committed" : "delivered")
        try await repository.savePublication(terminal,expectedRevision: current.revision)
    }
    public func shutdown() async {
        stopped = true; pump?.cancel(); await pump?.value; pump = nil
    }
}
