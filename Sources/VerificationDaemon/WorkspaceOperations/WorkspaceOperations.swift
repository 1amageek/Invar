import ArchitectureExtensions
import Foundation
import FormalValidation
import VerificationBackends
import VerificationCore
import VerificationDiscovery
import VerificationPlanner

public actor WorkspaceOperations: WorkspaceOperationExecuting, InputApplicabilityChecking, WatchInputProbing {
    private let source: any ArchitectureReading
    private let repository: any VerificationRepository
    private let resources: any WorkspaceResourceAdmitting
    private let workspace: URL
    private let workspaceID: String
    private let epoch: String
    private let engine: String
    private let defaultConfigurationPath: String?
    private let scratchFiles: Int
    private var stopped = false
    public init(source: any ArchitectureReading,repository: any VerificationRepository,resources: any WorkspaceResourceAdmitting,workspace: URL,workspaceID: String,epoch: String,engineIdentity: String,defaultConfigurationPath: String?,scratchFiles: Int) {
        self.source = source; self.repository = repository; self.resources = resources; self.workspace = workspace; self.workspaceID = workspaceID
        self.epoch = epoch; engine = engineIdentity; self.defaultConfigurationPath = defaultConfigurationPath; self.scratchFiles = scratchFiles
    }
    public func execute(_ demand: RunDemand,authority: OperationAuthority) async throws -> String {
        guard !stopped, demand.principal == authority.principal else { throw InvarError("POLICY_DENIED","Workspace operation authority differs or admission is closed",exitCode: 8) }
        let budget: RunBudget
        if case .preparePlan(_,_,let selected) = demand.request { budget = selected } else { budget = RunBudget() }
        try PlanValidation.budget(budget)
        let request = ResourceRequest(id: demand.id,memoryMiB: 1024,processes: 1,scratchBytes: budget.maximumWorkspaceBytes,priority: 0)
        try await resources.acquire(request)
        defer { await resources.release(demand.id) }
        try Task.checkCancellation()
        guard !stopped else { throw InvarError("CANCELLED","Workspace admission closed before operation start",exitCode: 130) }
        switch demand.request {
        case .openChange(let claim,let configurationPath):
            let captured = try await capture(configurationPath: configurationPath ?? defaultConfigurationPath)
            let input = try VerificationInput.reference(captured.inventory)
            let envelope: RequestEnvelope?
            if demand.origin == "internal" { envelope = try await repository.loadEnvelope(demand.envelopeID) } else { envelope = nil }
            let record = ChangeRecord(id: Canonical.parts("invar.change/2",[demand.id]),workspaceID: workspaceID,ownerPrincipal: authority.principal,sessionID: envelope?.sessionID,baseline: input,claim: claim,state: "open",revision: 1,sealedRevisionID: nil)
            try await repository.createChange(record); return record.id
        case .sealChange(let id): return try await seal(id,principal: authority.principal)
        case .preparePlan(let path,let changeRevisionID,_):
            let captured: CapturedWorkspace
            if let changeRevisionID {
                let revision = try await repository.loadChangeRevision(changeRevisionID)
                let change = try await repository.loadChange(revision.changeID)
                guard change.ownerPrincipal == authority.principal, revision.after.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Sealed change belongs to another principal/workspace",exitCode: 8) }
                captured = try await repository.capture(revision.after)
            } else { captured = try await capture(configurationPath: path) }
            return try await prepare(captured,path: path,demandID: demand.id,budget: budget)
        case .watch,.stopWatch: throw InvarError("INVALID_REQUEST","Hosting-owned watch operation reached source operations")
        case .verify,.reconcile,.cancel: throw InvarError("INVALID_REQUEST","Coordinator-owned operation reached workspace capture")
        }
    }
    private func capture(configurationPath: String?,extraPaths: [String] = [],projectSubject: String? = nil) async throws -> CapturedWorkspace {
        let augmented = try await readCapture(configurationPath: configurationPath,extraPaths: extraPaths,requestedProject: projectSubject)
        _ = try await repository.saveInput(augmented)
        let input = try VerificationInput.reference(augmented.inventory)
        _ = try await repository.observeInput(input,epoch: epoch)
        return augmented
    }
    private func readCapture(configurationPath: String?,extraPaths: [String] = [],requestedProject: String? = nil) async throws -> CapturedWorkspace {
        let files = WorkspaceContractFiles(workspace: workspace)
        var extras: [String:Data] = [:]
        var projectSubject = requestedProject
        if let configurationPath {
            let bytes = try files.read(configurationPath), configuration = try ConfigurationReader.decode(bytes)
            extras[configurationPath] = bytes; projectSubject = configuration.project?.subjectID
            let paths = configuration.formal.map(\.specification) + configuration.fuzz.map(\.corpus) + configuration.native.flatMap { $0.profile.harness } + configuration.fuzz.flatMap { $0.profile.harness } + (configuration.project?.contracts ?? [])
            for path in Set(paths) { extras[path] = try files.read(path) }
        }
        for path in extraPaths where extras[path] == nil { extras[path] = try files.read(path) }
        let original: CapturedWorkspace
        if let projectSubject {
            guard let projectSource = source as? any ProjectArchitectureReading else { throw InvarError("UNSUPPORTED_CAPABILITY","Source adapter cannot capture project inputs") }
            original = try await projectSource.captureProject(snapshotID: nil,entityID: projectSubject)
        } else { original = try await source.capture() }
        guard original.inventory.workspaceID == workspaceID else { throw InvarError("INPUT_MISMATCH","Source authority returned another workspace") }
        return try files.augment(original,inputs: extras)
    }
    func prepareModel(binding: ExtensionBinding,specification: String?) async throws -> String {
        let budget = RunBudget(), id = UUID().uuidString
        guard !stopped, binding.workspaceID == workspaceID, binding.entityIDs.count == 1,
            let selected = binding.entityIDs.first else { throw InvarError("INPUT_MISMATCH","Expected one source node in this workspace") }
        try await resources.acquire(ResourceRequest(id: id,memoryMiB: 1024,processes: 1,scratchBytes: budget.maximumWorkspaceBytes,priority: 0))
        defer { await resources.release(id) }
        try Task.checkCancellation()
        let original = try await source.capture()
        guard !stopped, original.inventory.workspaceID == binding.workspaceID, original.inventory.snapshotID == binding.snapshotID,
            let raw = original.inventory.originalRecords["inputManifest"]?.first,
            let entity = original.inventory.entities.first(where: { $0.id == selected }) else {
            throw InvarError("INPUT_MISMATCH","The selected source snapshot or node has changed")
        }
        let manifest = try JSONDecoder().decode(InputManifest.self,from: raw)
        guard try manifest.digest == binding.inputManifestDigest else { throw InvarError("INPUT_MISMATCH","The selected manifest has changed") }
        let declarations = ["type","function","method","field","extension","protocol"]
        let byID = "Verification/" + selected + "/properties.json"
        let named = "Verification/" + entity.name + "/properties.json"
        guard let specification else {
            guard manifest.files[byID] == nil, !declarations.contains(entity.kind) || entity.name.contains("/") || manifest.files[named] == nil else {
                throw InvarError("INPUT_MISMATCH","This node has indexed verification conditions. Reopen its menu to verify them.")
            }
            guard let path = entity.path, let entry = original.inventory.inputs.first(where: { $0.path == path }),
                manifest.files[path] == entry.digest, entity.sourceDigest == entry.digest else {
                throw InvarError("INPUT_UNAVAILABLE","The selected node has no recorded implementation in this snapshot")
            }
            guard entity.supportsModelSelection, FormalBackend.supportsModelLanguage(entity.language) else {
                throw InvarError("UNSUPPORTED_SOURCE_PROFILE","Select an implementation file, free function or supported Swift declaration")
            }
            let job = VerificationJob(id: "generate-model",backend: "modelGeneration",required: false,approved: true,
                inputs: [entry],memoryMiB: 1024,modelSource: entity)
            _ = try await repository.saveInput(original)
            let input = try VerificationInput.reference(original.inventory)
            let config = try VerificationConfiguration().identity()
            let body = PlanBody(input: input,executorIdentity: engine,configurationDigest: config,jobs: [job],budget: budget)
            let plan = try VerificationPlan(id: Canonical.identity(body),body: body)
            try await repository.savePlan(plan)
            return plan.id
        }
        guard let bytes = original.files[specification], manifest.files[specification] == Canonical.digest(bytes) else {
            throw InvarError("INPUT_MISMATCH","The specification must be present in the confirmed input manifest")
        }
        if specification != byID {
            guard manifest.files[byID] == nil, declarations.contains(entity.kind), !entity.name.contains("/"),
                specification == named,
                original.inventory.entities.lazy.filter({ declarations.contains($0.kind) && $0.name == entity.name }).prefix(2).count == 1 else {
                throw InvarError("INPUT_MISMATCH","Use the entity ID directory for an ambiguous declaration")
            }
        }
        let local = String(specification.dropLast("properties.json".count)) + "invar.json"
        let path: String, configBytes: Data
        if manifest.files[local] != nil {
            guard let indexed = original.files[local] else { throw InvarError("INPUT_UNAVAILABLE","Indexed node configuration is unavailable") }
            path = local; configBytes = indexed
        } else {
            guard let configured = defaultConfigurationPath else { throw InvarError("INPUT_UNAVAILABLE","Configure the node model beside its specification") }
            path = configured; configBytes = try WorkspaceContractFiles(workspace: workspace).read(path)
        }
        let config = try ConfigurationReader.decode(configBytes)
        guard !config.formal.isEmpty, config.formal.allSatisfy({ $0.specification == specification }),
            config.native.isEmpty, config.fuzz.isEmpty, config.architecture.isEmpty, config.project == nil else {
            throw InvarError("INVALID_REQUEST","Use a node-specific invar.json beside this specification to run only its formal checks")
        }
        let approval = try ContractApproval(configurationDigest: config.identity(),entries: [InputEntry(path: specification,digest: Canonical.digest(bytes),byteCount: bytes.count)])
        guard let policy = try await repository.loadPolicy(), policy.approvals.contains(approval) else {
            throw InvarError("APPROVAL_REQUIRED","The selected model configuration and specification require exact host approval")
        }
        let captured = try WorkspaceContractFiles(workspace: workspace).augment(original,inputs: [path:configBytes,specification:bytes])
        _ = try await repository.saveInput(captured)
        let input = try VerificationInput.reference(captured.inventory)
        _ = try await repository.observeInput(input,epoch: epoch)
        return try await prepare(captured,path: path,demandID: id,budget: budget)
    }
    func prepareProject(binding: ExtensionBinding,configurationPath: String) async throws -> String {
        guard !stopped, binding.workspaceID == workspaceID, binding.entityIDs.count == 1, let subject = binding.entityIDs.first else { throw InvarError("INPUT_MISMATCH","Project verification requires one original subject") }
        let files = WorkspaceContractFiles(workspace: workspace)
        let bytes = try files.read(configurationPath), configuration = try ConfigurationReader.decode(bytes)
        guard let project = configuration.project, project.subjectID == subject, project.approved,
            configuration.formal.isEmpty, configuration.native.isEmpty, configuration.fuzz.isEmpty, configuration.architecture.isEmpty else { throw InvarError("INVALID_CONFIGURATION","Use a project-only configuration for the selected workspace, system or container") }
        guard let projectSource = source as? any ProjectArchitectureReading else { throw InvarError("UNSUPPORTED_CAPABILITY","Source adapter cannot capture project inputs") }
        let original = try await projectSource.captureProject(snapshotID: binding.snapshotID,entityID: subject)
        guard original.inventory.snapshotID == binding.snapshotID, original.inventory.workspaceID == binding.workspaceID,
            original.inventory.entities.contains(where: { $0.id == subject }), let raw = original.inventory.originalRecords["inputManifest"]?.first else { throw InvarError("INPUT_MISMATCH","The selected project snapshot changed") }
        let manifest = try JSONDecoder().decode(InputManifest.self,from: raw)
        guard try manifest.digest == binding.inputManifestDigest else { throw InvarError("INPUT_MISMATCH","Project source manifest changed") }
        var extra = [configurationPath:bytes]
        for path in project.contracts { extra[path] = try files.read(path) }
        let captured = try files.augment(original,inputs: extra)
        _ = try await repository.saveInput(captured)
        let input = try VerificationInput.reference(captured.inventory)
        _ = try await repository.observeInput(input,epoch: epoch)
        return try await prepare(captured,path: configurationPath,demandID: UUID().uuidString,budget: project.budget)
    }
    private func seal(_ id: String,principal: String) async throws -> String {
        let change = try await repository.loadChange(id)
        guard change.workspaceID == workspaceID, change.ownerPrincipal == principal else { throw InvarError("POLICY_DENIED","Only the original principal may seal this change",exitCode: 8) }
        if let retained = change.sealedRevisionID { return retained }
        let before = try await repository.capture(change.baseline)
        let extras = before.inventory.metadata.keys.filter { $0.hasPrefix("@invar.extra:") }.map { String($0.dropFirst("@invar.extra:".count)) }
        let after = try await capture(configurationPath: nil,extraPaths: extras)
        var overlaps: [ChangeOverlap] = []
        let current = Dictionary(uniqueKeysWithValues: after.inventory.inputs.map { ($0.path,$0.digest) })
        for other in try await repository.openChanges(workspaceID: workspaceID) where other.id != change.id {
            let baseline = try await repository.inventory(other.baseline), old = Dictionary(uniqueKeysWithValues: baseline.inputs.map { ($0.path,$0.digest) })
            let paths = Set(old.keys).union(current.keys).filter { old[$0] != current[$0] }.sorted()
            overlaps.append(ChangeOverlap(changeID: other.id,paths: paths))
        }
        let request = ChangeAnalysisRequest(before: before,after: after,claim: change.claim,overlaps: overlaps,oraclePaths: extras,impactRelations: ["dependsOn","imports","calls"],budget: ChangeAnalysisBudget(maximumFiles: 250000,maximumBytes: 256 * 1024 * 1024,maximumRecords: 250000,maximumVisits: 250000,maximumOutputBytes: 8 * 1024 * 1024))
        let analysis = try ExactChangeAnalyzer().analyze(request)
        let afterInput = try VerificationInput.reference(after.inventory)
        let revision = try ChangeRevision.make(changeID: id,parentID: nil,before: change.baseline,after: afterInput,analysis: analysis)
        let sealed = try await repository.sealChange(revision,expectedRevision: change.revision)
        guard let retained = sealed.sealedRevisionID else { throw InvarError("STORE_INTEGRITY","Sealed change lost its immutable revision") }
        return retained
    }
    private func prepare(_ capture: CapturedWorkspace,path: String,demandID: String,budget: RunBudget) async throws -> String {
        _ = try Canonical.relative(path)
        guard let bytes = capture.files[path] else { throw InvarError("INPUT_UNAVAILABLE","Configuration was not captured in this sealed input") }
        let configuration = try ConfigurationReader.decode(bytes)
        let output = try await repository.outputRoot(for: demandID)
        let reservation = StorageReservation(id: demandID,relativeRoot: "runs/" + demandID,maximumBytes: budget.maximumWorkspaceBytes,maximumFiles: scratchFiles)
        try await repository.reserve(reservation)
        let result: Result<String,any Error>
        do {
            try FileManager.default.createDirectory(at: output,withIntermediateDirectories: false,attributes: [.posixPermissions: 0o700])
            let planID = try await build(capture,configuration: configuration,output: output,budget: budget)
            result = .success(planID)
        } catch { result = .failure(error) }
        do {
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            try await repository.releaseReservation(demandID)
        } catch { throw InvarError("CLEANUP_FAILED","Plan preparation result (\(result)); scratch cleanup failed (\(error))") }
        return try result.get()
    }
    private func build(_ capture: CapturedWorkspace,configuration: VerificationConfiguration,output: URL,budget: RunBudget) async throws -> String {
        var specifications: [String:Data] = [:], compilations: [String:PreparedFormalUnit] = [:], tools: [String:String] = [:]
        for check in configuration.formal {
            try Task.checkCancellation()
            guard let source = capture.files[check.source], let specification = capture.files[check.specification], let entry = capture.inventory.inputs.first(where: { $0.path == check.source }) else { throw InvarError("INPUT_UNAVAILABLE","Formal source/oracle was not captured") }
            specifications[check.id] = specification
            let languages = Set(capture.inventory.entities.filter { $0.kind == "file" && $0.path == check.source && $0.sourceDigest == entry.digest }.map(\.language))
            guard languages.count == 1, let language = languages.first else { throw InvarError("UNSUPPORTED_SOURCE_PROFILE","No unique exact source language binding",exitCode: 3) }
            let key = try PreparedFormalUnit.key(sourceDigest: entry.digest,language: language,executorIdentity: engine)
            if let retained = try await repository.loadPreparation(key) { compilations[check.id] = retained }
            else {
                let directory = output.appendingPathComponent(check.id)
                let unit = try await FormalBackend().prepare(source: source,language: language,executorIdentity: engine,output: directory,budget: budget)
                try await repository.adoptPreparation(unit,from: directory); compilations[check.id] = unit
            }
            if FileManager.default.fileExists(atPath: check.toolchain) { tools[check.id] = try FormalBackend().toolchainIdentity(at: check.toolchain) }
        }
        for check in configuration.fuzz {
            guard let bytes = capture.files[check.corpus] else { throw InvarError("INPUT_UNAVAILABLE","Corpus was not captured") }; specifications[check.id] = bytes
        }
        var native: [String:String] = [:]
        for (id,profile) in configuration.native.map({ ($0.id,$0.profile) }) + configuration.fuzz.map({ ($0.id,$0.profile) }) {
            let key = try NativeToolchain.configurationIdentity(profile)
            if let retained = native[key] { tools[id] = retained }
            else if FileManager.default.fileExists(atPath: profile.compiler), FileManager.default.fileExists(atPath: profile.sdk), FileManager.default.fileExists(atPath: profile.toolsDirectory) {
                let identity = try NativeToolchain.identity(profile); tools[id] = identity; native[key] = identity
            }
        }
        let input = try VerificationInput.reference(capture.inventory)
        let plan = try PlanBuilder().build(inventory: capture.inventory,inputID: input.id,executorIdentity: engine,configuration: configuration,specifications: specifications,compilations: compilations,toolchains: tools,budget: budget)
        try await repository.savePlan(plan)
        return plan.id
    }
    public func probe(configurationPath: String,planID: String,budget: RunBudget) async throws -> WatchInputProbe {
        guard !stopped else { throw InvarError("COORDINATOR_STOPPED","Watch probe admission is closed") }
        try PlanValidation.budget(budget)
        let id = UUID().uuidString
        try await resources.acquire(ResourceRequest(id: id,memoryMiB: 1024,processes: 0,scratchBytes: 0,priority: 1))
        defer { await resources.release(id) }
        try Task.checkCancellation()
        guard !stopped else { throw InvarError("CANCELLED","Watch probe admission closed",exitCode: 130) }
        let plan = try await repository.loadPlan(planID)
        guard plan.body.input.workspaceID == workspaceID, plan.body.budget == budget else { throw InvarError("INPUT_MISMATCH","Watch probe differs from its retained workspace/budget") }
        let captured = try await readCapture(configurationPath: configurationPath)
        let semantic = try InputIdentity.digest(captured.inventory)
        guard semantic == plan.body.input.semanticDigest else { return WatchInputProbe(changed: true,reason: "Captured source/context/contracts changed") }
        var formal: [String:String] = [:], native: [String:String] = [:]
        for job in plan.body.jobs {
            let current: String?
            if let check = job.formal {
                if let cached = formal[check.toolchain] { current = cached }
                else if FileManager.default.fileExists(atPath: check.toolchain) {
                    let identity = try FormalBackend().toolchainIdentity(at: check.toolchain)
                    formal[check.toolchain] = identity; current = identity
                } else { current = nil }
            } else if let profile = job.native?.profile ?? job.fuzz?.profile {
                let key = try NativeToolchain.configurationIdentity(profile)
                if let cached = native[key] { current = cached }
                else if FileManager.default.fileExists(atPath: profile.compiler), FileManager.default.fileExists(atPath: profile.sdk), FileManager.default.fileExists(atPath: profile.toolsDirectory) {
                    let identity = try NativeToolchain.identity(profile); native[key] = identity; current = identity
                } else { current = nil }
            } else { continue }
            if current != job.toolchainIdentity { return WatchInputProbe(changed: true,reason: "Installed tool identity changed or became unavailable") }
        }
        return WatchInputProbe(changed: false,reason: nil)
    }
    public func applicability(of plan: SchedulingPlan) async throws -> InputComparison {
        let id = UUID().uuidString
        try await resources.acquire(ResourceRequest(id: id,memoryMiB: 1024,processes: 1,scratchBytes: plan.budget.maximumWorkspaceBytes,priority: 0))
        defer { await resources.release(id) }
        let original = try await repository.inventory(plan.input)
        let extras = original.metadata.keys.filter { $0.hasPrefix("@invar.extra:") }.map { String($0.dropFirst("@invar.extra:".count)) }
        let projectSubject: String?
        if let job = plan.jobs.first(where: { $0.backend == "project" }) { projectSubject = try await repository.loadDescriptor(job.descriptorID).job.project?.subjectID }
        else { projectSubject = nil }
        let current = try await capture(configurationPath: nil,extraPaths: extras,projectSubject: projectSubject)
        let target = try VerificationInput.reference(current.inventory)
        return InputComparison(target: target,status: target.semanticDigest == plan.input.semanticDigest ? "matchesInputs" : "stale",basis: "Exact current source and independently captured contract digest",unknownBoundaries: target.dependencyStatus == "unknown" ? ["Upstream project dependency closure remains unknown"] : [])
    }
    public func closeAdmission() { stopped = true }
    public func shutdown() { stopped = true }
}
