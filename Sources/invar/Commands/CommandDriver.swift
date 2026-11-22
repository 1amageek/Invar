import ArchitectureCore
import Foundation
import VerificationClient
import VerificationCore

struct CommandDriver {
    let options: CommandOptions
    func execute() async throws -> (Data,Int32) {
        if options.command == "capabilities" {
            let report: JSONValue = .object(["schemaVersion":.number(2),"product":.string("Invar"),"host":.string("macOS27 arm64"),"executionOwner":.string("workspace daemon"),"translation":.string("UNVALIDATED generated-model correspondence"),"sourceAuthority":.string("authenticated ArchitectureExplorer"),"transport":.string("private same-user Unix sockets"),"nativeProfile":.string("swift-modules-json/1"),"formalProfiles":.string("finite/quantified scalar Swift and Rust; original TLA/Lean evidence graphs")])
            let bytes = try CanonicalJSON.encode(report)
            return (bytes,0)
        }
        let client = try await ClientConnection(options: options).connect()
        defer { await client.shutdown() }
        let result: (Data,Int32)
        switch options.command {
        case "current":
            let value = try await client.currentView()
            result = (try Canonical.encode(value),0)
        case "source-status":
            let value = try await client.sourceHead()
            result = (try Canonical.encode(value),0)
        case "operation":
            let id = try options.required("operation-id")
            let value = try await client.operation(id)
            result = (try Canonical.encode(value),0)
        case "receipt":
            let id = try options.required("envelope-id")
            let value = try await client.receipt(envelopeID: id)
            result = (try Canonical.encode(value),0)
        case "plan-info":
            let id = try options.required("plan")
            let value = try await client.plan(id)
            result = (try Canonical.encode(value),0)
        case "report":
            let id = try options.required("run")
            let value = try await client.run(id)
            result = (try Canonical.encode(value),0)
        case "view":
            let id = try options.required("view-id")
            let value = try await client.view(id)
            result = (try Canonical.encode(value),0)
        case "evidence":
            let id = try options.required("evidence-id")
            let value = try await client.evidenceSummary(id)
            result = (try Canonical.encode(value),0)
        case "provider-action":
            let id = try options.required("action-id")
            let value = try await client.providerAction(id)
            result = (try Canonical.encode(value),0)
        case "publication":
            let id = try options.required("operation-id")
            let value = try await client.publication(id)
            result = (try Canonical.encode(value),0)
        case "change":
            let id = try options.required("change")
            let value = try await client.change(id)
            result = (try Canonical.encode(value),0)
        case "change-revision":
            let id = try options.required("change-revision")
            let value = try await client.changeRevision(id)
            result = (try Canonical.encode(value),0)
        case "watch-status":
            let id = try options.required("watch-id")
            let value = try await client.watch(id)
            result = (try Canonical.encode(value),0)
        case "watches":
            let value = try await client.watches()
            result = (try Canonical.encode(value),0)
        case "ci": result = try await ci(client)
        default:
            let budget = try options.budget(), operation = try await operation(client,budget: budget)
            let key = try options.required("key")
            let prepared = try await client.prepare(operation,key: key,timeout: budget.runTimeoutSeconds)
            let receipt = try await client.accept(prepared)
            if options.values["wait"] == "true" {
                let terminal = try await wait(receipt,client: client,seconds: budget.runTimeoutSeconds+5)
                result = (try Canonical.encode(terminal),terminal.state == "completed" ? 0 : terminal.failure?.exitCode ?? 6)
            } else { result = (try Canonical.encode(receipt),0) }
        }
        if let output = options.values["out"] {
            let path = URL(fileURLWithPath: output)
            guard !FileManager.default.fileExists(atPath: path.path) else { throw InvarError("OUTPUT_EXISTS","Output path already exists",exitCode: 2) }
            try result.0.write(to: path,options: .withoutOverwriting)
        }
        return result
    }
    private func operation(_ client: LocalVerificationClient,budget: RunBudget) async throws -> WorkspaceOperation {
        switch options.command {
        case "change-open": return .openChange(claim: nil,configurationPath: options.values["contracts"])
        case "change-seal":
            let id = try options.required("change")
            return .sealChange(changeID: id)
        case "plan":
            let path = try options.required("contracts")
            return .preparePlan(configurationPath: path,changeRevisionID: options.values["change-revision"],budget: budget)
        case "run":
            let id = try options.required("plan")
            return .verify(planID: id,changeRevisionID: options.values["change-revision"],replayOfRunID: nil)
        case "replay":
            let runID = try options.required("run"), run = try await client.run(runID)
            return .verify(planID: run.planID,changeRevisionID: nil,replayOfRunID: runID)
        case "cancel":
            let id = try options.required("operation-id")
            return .cancel(demandID: id)
        case "watch":
            let path = try options.required("contracts")
            return .watch(configurationPath: path,budget: budget)
        case "watch-stop":
            let id = try options.required("watch-id")
            return .stopWatch(watchID: id)
        default: throw InvarError("INVALID_ARGUMENT","Unknown mutating SDK command",exitCode: 2)
        }
    }
    private func wait(_ receipt: OperationReceipt,client: LocalVerificationClient,seconds: Double) async throws -> RunDemand {
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
            while true {
                try Task.checkCancellation()
                let value = try await client.operation(receipt.operationID)
                if !["queued","running","cancelling"].contains(value.state) { return value }
                guard ContinuousClock.now < deadline else { throw InvarError("OBSERVATION_TIMEOUT","Observation ended; the original receipt remains valid",exitCode: 6) }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            let cause = error as? InvarError ?? InvarError(error is CancellationError ? "CANCELLED" : "OBSERVATION_FAILED",String(describing: error),exitCode: error is CancellationError ? 130 : 6)
            throw CommandObservationError(receipt: receipt,cause: cause)
        }
    }
    private func ci(_ client: LocalVerificationClient) async throws -> (Data,Int32) {
        let key = try options.required("key"), path = try options.required("contracts"), budget = try options.budget()
        guard key.utf8.count <= 110 else { throw InvarError("INVALID_ARGUMENT","CI key must leave room for its fixed stage suffixes",exitCode: 2) }
        let preparation = try await client.preparePlan(configurationPath: path,changeRevisionID: options.values["change-revision"],budget: budget,key: key + ".plan",timeout: budget.runTimeoutSeconds)
        let prepared = try await wait(preparation,client: client,seconds: budget.runTimeoutSeconds+5)
        guard prepared.state == "completed", let planID = prepared.resultID else { return (try Canonical.encode(prepared),prepared.failure?.exitCode ?? 6) }
        let receipt = try await client.verify(planID: planID,changeRevisionID: options.values["change-revision"],replayOfRunID: nil,key: key + ".run",timeout: budget.runTimeoutSeconds)
        let terminal = try await wait(receipt,client: client,seconds: budget.runTimeoutSeconds+5)
        guard terminal.state == "completed", let runID = terminal.resultID else { return (try Canonical.encode(terminal),terminal.failure?.exitCode ?? 6) }
        let run = try await client.run(runID), bytes = try Canonical.encode(run)
        let incomplete = run.attempts.contains { $0.execution != "completed" || ["unknown","notEvaluated"].contains($0.outcome) }
        return (bytes,run.acceptedAtCompletion ? 0 : incomplete ? 6 : 5)
    }
}
