import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    func publishPlanMetadata(_ plan: VerificationPlan) throws {
        let metadata = try SchedulingPlan(plan)
        let bytes = try Canonical.encode(metadata), digest = Canonical.digest(bytes)
        let index = try Canonical.encode(digest)
        try database.insert("schedulingPlan",id: digest,bytes: bytes)
        try database.insert("schedulingPlanIndex",id: plan.id,bytes: index)
        try database.link(ownerKind: "plan",ownerID: plan.id,targetKind: "schedulingPlanIndex",targetID: plan.id)
        try database.link(ownerKind: "schedulingPlanIndex",ownerID: plan.id,targetKind: "schedulingPlan",targetID: digest)
        for job in plan.body.jobs {
            let descriptor = ExecutionBinding.descriptor(plan: plan,job: job)
            let reference = try JobReference(descriptor), descriptorID = reference.descriptorID
            let encoded = try Canonical.encode(descriptor)
            guard encoded.count <= 1_048_576 else { throw InvarError("RESOURCE_LIMIT","Sealed worker descriptor exceeds its bounded profile",exitCode: 6) }
            try database.insert("descriptor",id: descriptorID,bytes: encoded)
            try database.link(ownerKind: "descriptor",ownerID: descriptorID,targetKind: "plan",targetID: plan.id)
            let bytes = try Canonical.encode(reference), id = Canonical.digest(bytes)
            let index = try Canonical.encode(id)
            try database.insert("jobReference",id: id,bytes: bytes)
            try database.insert("jobReferenceIndex",id: descriptorID,bytes: index)
            try database.link(ownerKind: "plan",ownerID: plan.id,targetKind: "jobReferenceIndex",targetID: descriptorID)
            try database.link(ownerKind: "jobReferenceIndex",ownerID: descriptorID,targetKind: "jobReference",targetID: id)
            try database.link(ownerKind: "jobReference",ownerID: id,targetKind: "descriptor",targetID: descriptorID)
        }
    }
    public func schedulingPlan(_ id: String) throws -> SchedulingPlan {
        try ensureAccepting(); try safeID(id)
        guard let index = try database.load("schedulingPlanIndex",id: id) else { throw InvarError("PLAN_NOT_FOUND","Unknown sealed scheduling plan") }
        let digest = try JSONDecoder().decode(String.self,from: index)
        guard let bytes = try database.load("schedulingPlan",id: digest), bytes.count <= SchedulingPlan.maximumMetadataBytes, Canonical.digest(bytes) == digest else { throw InvarError("STORE_INTEGRITY","Scheduling plan metadata digest/size differs") }
        let value = try JSONDecoder().decode(SchedulingPlan.self,from: bytes)
        guard value.id == id, value.schemaVersion == 2, value.jobs.count > 0, value.jobs.count <= 500,
            value.jobs.allSatisfy({ $0.planID == id }), Set(value.jobs.map(\.id)).count == value.jobs.count else { throw InvarError("STORE_INTEGRITY","Scheduling plan identity/schema differs") }
        let input = try inputReference(value.input.id)
        guard value.input == input else { throw InvarError("STORE_INTEGRITY","Scheduling input binding differs") }
        return value
    }
    public func jobReference(_ descriptorID: String) throws -> JobReference {
        try ensureAccepting(); try safeID(descriptorID)
        guard let index = try database.load("jobReferenceIndex",id: descriptorID) else { throw InvarError("DESCRIPTOR_NOT_FOUND","Unknown admitted job reference") }
        let digest = try JSONDecoder().decode(String.self,from: index)
        guard let bytes = try database.load("jobReference",id: digest), Canonical.digest(bytes) == digest else { throw InvarError("STORE_INTEGRITY","Job reference metadata digest differs") }
        let value = try JSONDecoder().decode(JobReference.self,from: bytes)
        guard value.descriptorID == descriptorID else { throw InvarError("STORE_INTEGRITY","Job reference targets another descriptor") }
        return value
    }
    public func attachExecution(_ executionID: String,to demandID: String,jobID: String) throws {
        try ensureAccepting()
        try transaction {
            let demand = try loadDemand(demandID), execution = try loadExecution(executionID)
            if demand.executionIDs.contains(executionID) { return }
            guard demand.state == "running", let planID = demand.planID else { throw InvarError("CANCELLED","Demand stopped before execution interest attachment",exitCode: 130) }
            let plan = try schedulingPlan(planID)
            guard let target = plan.jobs.first(where: { $0.id == jobID }), execution.jobID == jobID,
                execution.descriptorID == target.descriptorID || target.executionKey != nil && target.executionKey == execution.inputKey else { throw InvarError("INPUT_MISMATCH","Shared execution differs from the demand's complete scoped job") }
            let ids = Array(Set(demand.executionIDs + [executionID])).sorted()
            let next = demand.transitioning(to: "running",executionIDs: ids)
            try transitionDemand(next,expectedRevision: demand.revision)
        }
    }
}
