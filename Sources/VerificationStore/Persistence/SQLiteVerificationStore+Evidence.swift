import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func inputReference(_ id: String) throws -> VerificationInput {
        try safeID(id)
        let exists = try database.scalar("SELECT count(*) FROM records WHERE namespace='input' AND id=?",strings: [id])
        guard exists == 1 else { throw InvarError("INPUT_UNAVAILABLE","Retained source input has been retired") }
        guard let bytes = try database.load("input",id: id) else { throw InvarError("INPUT_UNAVAILABLE","Unknown retained input reference") }
        let value = try JSONDecoder().decode(VerificationInput.self,from: bytes)
        guard value.id == id, value.manifestDigest == id else { throw InvarError("STORE_INTEGRITY","Input reference differs from catalog binding") }
        return value
    }
    public func saveEvidence(_ value: VerificationEvidence) throws {
        try ensureAccepting()
        _ = try inputReference(value.inputID)
        if let id = value.descriptorID {
            let descriptor = try loadDescriptor(id)
            let key = try ExecutionBinding.key(descriptor)
            guard descriptor.input.id == value.inputID, descriptor.job.id == value.jobID, value.executionKey == key else { throw InvarError("INVALID_RESULT","Evidence execution binding differs") }
            guard let executionID = value.executionID else { throw InvarError("INVALID_RESULT","Sealed evidence lacks physical execution identity") }
            let execution = try loadExecution(executionID)
            guard execution.descriptorID == id, execution.jobID == value.jobID else { throw InvarError("INVALID_RESULT","Sealed evidence names another execution") }
            try PlanValidation.evidence(value,job: descriptor.job)
        } else if value.executionKey != nil { throw InvarError("INVALID_RESULT","Execution key lacks its original descriptor") }
        for reference in value.artifacts { _ = try artifactRoot(reference) }
        let bytes = try Canonical.encode(value)
        try database.insert("evidence",id: value.id,bytes: bytes)
        try database.link(ownerKind: "evidence",ownerID: value.id,targetKind: "input",targetID: value.inputID)
        if let id = value.executionID { try database.link(ownerKind: "evidence",ownerID: value.id,targetKind: "execution",targetID: id) }
        if let id = value.descriptorID { try database.link(ownerKind: "evidence",ownerID: value.id,targetKind: "descriptor",targetID: id) }
        for reference in value.artifacts { try database.link(ownerKind: "evidence",ownerID: value.id,targetKind: "artifact",targetID: reference.id) }
    }
    public func loadEvidence(_ id: String) throws -> VerificationEvidence {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("evidence",id: id) else { throw InvarError("EVIDENCE_NOT_FOUND","Unknown immutable evidence") }
        let value = try JSONDecoder().decode(VerificationEvidence.self,from: bytes)
        guard value.id == id else { throw InvarError("STORE_INTEGRITY","Evidence key differs from immutable bytes") }
        return value
    }
    public func saveAssociation(_ value: EvidenceAssociation) throws {
        try ensureAccepting()
        let evidence = try loadEvidence(value.evidenceID)
        let original = try inputReference(evidence.inputID), target = try inputReference(value.input.id)
        let expected = EvidenceAssociation.make(evidence: evidence,targetDescriptorID: value.targetDescriptorID,changeRevisionID: value.changeRevisionID,input: value.input,status: value.applicability,basis: value.basis,unknownBoundaries: value.unknownBoundaries,reuseDecision: value.reuseDecision)
        var scopedMatch = false
        if let id = value.targetDescriptorID {
            let descriptor = try loadDescriptor(id)
            let key = try ExecutionBinding.key(descriptor)
            guard descriptor.input == target, descriptor.job.id == evidence.jobID else { throw InvarError("INVALID_RESULT","Association target descriptor differs") }
            scopedMatch = key != nil && key == evidence.executionKey
        }
        guard value == expected, target == value.input, original.workspaceID == target.workspaceID, ["matchesInputs","stale","unknown","unmatched"].contains(value.applicability), value.applicability != "matchesInputs" || (original.semanticDigest == target.semanticDigest || scopedMatch) else { throw InvarError("INVALID_RESULT","Association comparison is inconsistent") }
        if let revision = value.changeRevisionID { _ = try loadChangeRevision(revision) }
        let bytes = try Canonical.encode(value)
        try database.insert("association",id: value.id,bytes: bytes)
        try database.link(ownerKind: "association",ownerID: value.id,targetKind: "evidence",targetID: evidence.id)
        try database.link(ownerKind: "association",ownerID: value.id,targetKind: "input",targetID: value.input.id)
        if let id = value.targetDescriptorID { try database.link(ownerKind: "association",ownerID: value.id,targetKind: "descriptor",targetID: id) }
    }
    public func loadAssociation(_ id: String) throws -> EvidenceAssociation {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("association",id: id) else { throw InvarError("EVIDENCE_NOT_FOUND","Unknown evidence association") }
        let value = try JSONDecoder().decode(EvidenceAssociation.self,from: bytes)
        guard value.id == id else { throw InvarError("STORE_INTEGRITY","Association identity differs") }; return value
    }
    public func sourceHead(workspaceID: String) throws -> SourceHead? {
        try ensureAccepting()
        let key = Canonical.parts("invar.source-workspace/2",[workspaceID])
        guard let head = try database.head("source",id: key), let bytes = try database.load("source",id: head.recordID) else { return nil }
        let value = try JSONDecoder().decode(SourceHead.self,from: bytes)
        guard value.id == head.recordID, value.workspaceID == workspaceID, value.revision == head.revision else { throw InvarError("STORE_INTEGRITY","Source head differs from immutable revision") }
        return value
    }
    public func nextViewSequence(workspaceID: String) throws -> Int {
        try ensureAccepting()
        let key = Canonical.parts("invar.view-head/2",[workspaceID])
        let current = try database.head("view",id: key)
        guard (current?.revision ?? 0) < Int.max else { throw InvarError("RESOURCE_LIMIT","View sequence exhausted",exitCode: 6) }
        return (current?.revision ?? 0) + 1
    }
    public func observeInput(_ input: VerificationInput,epoch: String) throws -> SourceHead {
        try ensureAccepting()
        guard epoch == activeEpoch, try inputReference(input.id) == input else { throw InvarError("INPUT_MISMATCH","Source observation epoch/input differs") }
        return try advanceSource(input,epoch: epoch,confirmed: true,reason: nil)
    }
    public func invalidateSource(workspaceID: String,epoch: String,reason: String) throws -> SourceHead? {
        try ensureAccepting()
        guard epoch == activeEpoch, !reason.isEmpty, reason.utf8.count <= 1024 else { throw InvarError("INPUT_MISMATCH","Invalid source invalidation epoch/reason") }
        guard let current = try sourceHead(workspaceID: workspaceID) else { return nil }
        return try advanceSource(current.input,epoch: epoch,confirmed: false,reason: reason)
    }
    private func advanceSource(_ input: VerificationInput,epoch: String,confirmed: Bool,reason: String?) throws -> SourceHead {
        return try transaction {
            let current = try sourceHead(workspaceID: input.workspaceID)
            if let current, current.input.sourceIdentity == input.sourceIdentity, current.daemonEpoch == epoch, current.confirmed == confirmed, current.reason == reason { return current }
            guard (current?.revision ?? 0) < Int.max else { throw InvarError("RESOURCE_LIMIT","Source revision exhausted",exitCode: 6) }
            let next = SourceHead(workspaceID: input.workspaceID,input: input,daemonEpoch: epoch,revision: (current?.revision ?? 0) + 1,confirmed: confirmed,reason: reason)
            let bytes = try Canonical.encode(next), key = Canonical.parts("invar.source-workspace/2",[input.workspaceID])
            try database.insert("source",id: next.id,bytes: bytes)
            try database.advance("source",id: key,expectedRevision: current?.revision ?? 0,recordID: next.id)
            try database.link(ownerKind: "source",ownerID: next.id,targetKind: "input",targetID: input.id)
            let previous = try latestAssessment(workspaceID: input.workspaceID)
            let old: ChangeVerificationView?
            if let previous { old = try loadView(previous.id) } else { old = nil }
            var associations: [EvidenceAssociation] = []
            for id in old?.evidenceIDs ?? [] {
                let evidence = try loadEvidence(id)
                associations.append(EvidenceAssociation.make(evidence: evidence,changeRevisionID: nil,input: input,status: "unknown",basis: reason ?? "New source observation; scoped comparison pending",unknownBoundaries: [reason ?? "Uncompared source observation"],reuseDecision: "historicalEvidence"))
            }
            let view = ChangeVerificationView(workspaceID: input.workspaceID,changeRevisionID: nil,input: input,daemonEpoch: epoch,sourceRevision: next.revision,sequence: try nextViewSequence(workspaceID: input.workspaceID),delta: nil,impactEntityIDs: [],unknownBoundaries: [reason ?? "Uncompared source observation"],planIDs: old?.planIDs ?? [],runIDs: old?.runIDs ?? [],evidenceIDs: old?.evidenceIDs ?? [],associations: associations,pendingDemandIDs: [],diagnostics: [reason ?? "Source observation advanced; previous results remain historical"])
            _ = try commitView(view)
            return next
        }
    }
    public func commitView(_ value: ChangeVerificationView) throws -> ViewReference {
        try ensureAccepting()
        return try transaction {
            guard value.daemonEpoch == activeEpoch, value.input.workspaceID == value.workspaceID else { throw InvarError("INVALID_RESULT","View epoch/workspace differs") }
            let input = try inputReference(value.input.id)
            guard input == value.input else { throw InvarError("INPUT_MISMATCH","View input differs") }
            if let change = value.changeRevisionID { _ = try loadChangeRevision(change) }
            let key = Canonical.parts("invar.view-head/2",[value.workspaceID])
            let current = try database.head("view",id: key)
            guard value.sequence == (current?.revision ?? 0) + 1 else { throw InvarError("REVISION_CONFLICT","Common view changed during composition") }
            guard Set(value.evidenceIDs).count == value.evidenceIDs.count, value.associations.count == value.evidenceIDs.count, Set(value.associations.map(\.evidenceID)) == Set(value.evidenceIDs) else { throw InvarError("INVALID_RESULT","View lost or duplicated evidence associations") }
            for evidence in value.evidenceIDs { _ = try loadEvidence(evidence) }
            for association in value.associations {
                guard value.evidenceIDs.contains(association.evidenceID), association.input == value.input else { throw InvarError("INVALID_RESULT","View association lacks its evidence") }
                try saveAssociation(association)
            }
            for plan in value.planIDs {
                _ = try schedulingPlan(plan)
            }
            for run in value.runIDs { _ = try loadRun(run) }
            let reference = try value.reference(), bytes = try Canonical.encode(value)
            try database.insert("view",id: reference.id,bytes: bytes)
            try database.advance("view",id: key,expectedRevision: current?.revision ?? 0,recordID: reference.id)
            try database.link(ownerKind: "view",ownerID: reference.id,targetKind: "input",targetID: value.input.id)
            for evidence in value.evidenceIDs { try database.link(ownerKind: "view",ownerID: reference.id,targetKind: "evidence",targetID: evidence) }
            for association in value.associations { try database.link(ownerKind: "view",ownerID: reference.id,targetKind: "association",targetID: association.id) }
            for plan in value.planIDs { try database.link(ownerKind: "view",ownerID: reference.id,targetKind: "plan",targetID: plan) }
            for run in value.runIDs { try database.link(ownerKind: "view",ownerID: reference.id,targetKind: "run",targetID: run) }
            if let change = value.changeRevisionID { try database.link(ownerKind: "view",ownerID: reference.id,targetKind: "changeRevision",targetID: change) }
            return reference
        }
    }
    public func loadView(_ id: String) throws -> ChangeVerificationView {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("view",id: id) else { throw InvarError("VIEW_NOT_FOUND","Unknown committed view") }
        let value = try JSONDecoder().decode(ChangeVerificationView.self,from: bytes)
        let reference = try value.reference()
        guard reference.id == id else { throw InvarError("STORE_INTEGRITY","View digest differs from immutable content") }; return value
    }
    func latestAssessment(workspaceID: String) throws -> ViewReference? {
        try ensureAccepting()
        let key = Canonical.parts("invar.view-head/2",[workspaceID])
        guard let current = try database.head("view",id: key) else { return nil }
        let value = try loadView(current.recordID)
        return try value.reference()
    }
    public func latestView(workspaceID: String) throws -> ViewReference? {
        try publishedHead(workspaceID: workspaceID)?.view
    }
    public func completeDemand(_ demand: RunDemand,run: VerificationRun?,view: ChangeVerificationView?,publication: PublicationRecord?,expectedRevision: Int) throws {
        try ensureAccepting()
        let failureTerminal = ["failed","cancelled","interrupted","notStarted","outcomeUnknown"].contains(demand.state)
        try transaction(usingFailureReserve: failureTerminal) {
            if failureTerminal { try abortWatchRegistration(demand) }
            if let run {
                guard case .verify = demand.request else { throw InvarError("INVALID_RESULT","Only verification creates a new execution run") }
                guard demand.state == "completed", demand.resultID == run.id, demand.planID == run.planID, Set(run.attempts.compactMap(\.executionID)).isSubset(of: Set(demand.executionIDs)) else { throw InvarError("INVALID_RESULT","Terminal demand differs from its run") }
                try saveRun(run)
                if case .verify(_,_,let replay,_) = demand.request, let replay { try saveReplay(originalRunID: replay,replayRunID: run.id) }
            }
            if demand.state == "completed", run == nil {
                guard let id = demand.resultID else { throw InvarError("INVALID_RESULT","Completed operation lacks result identity") }
                switch demand.request {
                case .reconcile(let planID,let runID):
                    let run = try loadRun(runID), original = try schedulingPlan(run.planID), target = try schedulingPlan(planID)
                    let expected = try EvidenceReconciliation.associations(run: run,original: original,target: target)
                    guard let view, id == (try view.reference()).id, demand.planID == planID, view.input == target.input, view.changeRevisionID == nil,
                        view.planIDs == [planID], view.runIDs == [runID], view.evidenceIDs == run.attempts.map(\.id), view.associations == expected,
                        view.sourceRevision == demand.sourceRevision, demand.executionIDs.isEmpty else { throw InvarError("INVALID_RESULT","Reassociation differs from its original completed scope/view") }
                case .verify: throw InvarError("INVALID_RESULT","Verification completion lacks its atomic run")
                case .preparePlan: _ = try schedulingPlan(id)
                case .openChange: _ = try loadChange(id)
                case .sealChange: _ = try loadChangeRevision(id)
                case .cancel: _ = try loadDemand(id)
                case .watch(let path,let budget):
                    let watch = try loadWatch(id)
                    guard watch.id == demand.id, watch.principal == demand.principal, watch.configurationPath == path, watch.budget == budget else { throw InvarError("INVALID_RESULT","Watch result differs from its registration demand") }
                    try completeWatchRegistration(id,demand: demand)
                case .stopWatch(let requested):
                    let watch = try loadWatch(id)
                    guard id == requested, watch.principal == demand.principal, ["stopped","expired"].contains(watch.state) else { throw InvarError("INVALID_RESULT","Watch stop lacks an inactive owned registration") }
                }
            }
            let committed: RunDemand
            if let view {
                let reference = try view.reference()
                guard demand.state == "completed", demand.view == nil || demand.view == reference else { throw InvarError("INVALID_RESULT","Operation's view differs from its atomic result") }
                _ = try commitView(view); committed = demand.bindingView(reference)
            } else {
                guard demand.view == nil else { throw InvarError("INVALID_RESULT","Operation cannot attach a view outside the atomic result transaction") }
                committed = demand
            }
            if let publication {
                guard let view, publication.id == demand.id, publication.view == (try view.reference()), ["ready","blocked"].contains(publication.state) else { throw InvarError("INVALID_PUBLICATION","Outbox differs from atomic demand/view") }
                try savePublication(publication,expectedRevision: publication.revision-1)
            }
            try transitionDemand(committed,expectedRevision: expectedRevision,allowCompletion: true)
        }
    }
    public func completeExecution(_ execution: ExecutionRecord,evidence: VerificationEvidence,expectedRevision: Int) throws {
        try ensureAccepting()
        try transaction {
            guard execution.state == "completed", execution.evidenceID == evidence.id, execution.jobID == evidence.jobID, execution.descriptorID == evidence.descriptorID, (evidence.executionID == nil || evidence.executionID == execution.id) else { throw InvarError("INVALID_RESULT","Terminal execution differs from evidence") }
            try saveEvidence(evidence)
            try saveExecution(execution,expectedRevision: expectedRevision)
            if let key = evidence.executionKey, evidence.execution == "completed" {
                guard execution.inputKey == key else { throw InvarError("INVALID_RESULT","Execution key differs from sealed evidence") }
                let current = try database.head("executionCache",id: key)
                let bytes = try Canonical.encode(["key":key,"evidenceID":evidence.id])
                let rowID = Canonical.parts("invar.execution-cache/2",[key,evidence.id])
                try database.insert("executionCache",id: rowID,bytes: bytes)
                try database.advance("executionCache",id: key,expectedRevision: current?.revision ?? 0,recordID: rowID)
                try database.link(ownerKind: "executionCache",ownerID: rowID,targetKind: "evidence",targetID: evidence.id)
            }
        }
    }
}
