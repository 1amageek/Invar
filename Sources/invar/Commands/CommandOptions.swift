import Foundation
import VerificationCore

struct CommandOptions: Sendable {
    let command: String
    let values: [String:String]
    init(_ arguments: [String]) throws {
        let commands: Set<String> = ["capabilities","status","change-open","change-seal","change","change-revision","plan","plan-info","run","ci","report","replay","operation","receipt","cancel","watch","watch-stop","watch-status","watches","current","source-status","view","evidence","publication","provider-action","mcp"]
        guard let command = arguments.first, commands.contains(command) else { throw InvarError("INVALID_ARGUMENT","Unknown daemon SDK command",exitCode: 2) }
        self.command = command
        let allowed: Set<String> = ["workspace","state","client-state","client-profile","capabilities","contracts","plan","run","change","change-revision","operation-id","action-id","envelope-id","watch-id","view-id","evidence-id","key","wait","out","workers","memory-mib","timeout","run-timeout","processes","cpu-seconds","scratch-mib"]
        var values: [String:String] = [:], index = 1
        while index < arguments.count {
            let argument = arguments[index], key = String(argument.dropFirst(2))
            guard argument.hasPrefix("--"), allowed.contains(key), index+1 < arguments.count, !arguments[index+1].hasPrefix("--"), values[key] == nil else { throw InvarError("INVALID_ARGUMENT","Unknown, repeated or missing option: " + argument,exitCode: 2) }
            values[key] = arguments[index+1]; index += 2
        }
        if let wait = values["wait"], !["true","false"].contains(wait) { throw InvarError("INVALID_ARGUMENT","--wait expects true or false",exitCode: 2) }
        self.values = values
    }
    var workspace: URL { URL(fileURLWithPath: values["workspace"] ?? FileManager.default.currentDirectoryPath).standardizedFileURL.resolvingSymlinksInPath() }
    func required(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty, value.utf8.count <= 1024 else { throw InvarError("INVALID_ARGUMENT","Missing bounded --" + key,exitCode: 2) }
        return value
    }
    func capabilities() throws -> Set<WorkspaceCapability> {
        guard let text = values["capabilities"] else { return [.read,.changes,.planning,.verification,.watching] }
        let names = text.split(separator: ",",omittingEmptySubsequences: false).map(String.init)
        let values = names.compactMap(WorkspaceCapability.init(rawValue:))
        guard values.count == names.count, !values.isEmpty, Set(values).count == values.count, !values.contains(.administration) else { throw InvarError("INVALID_ARGUMENT","Choose distinct ordinary SDK capability names",exitCode: 2) }
        return Set(values)
    }
    func integer(_ key: String,default fallback: Int) throws -> Int {
        guard let text = values[key] else { return fallback }
        guard let value = Int(text) else { throw InvarError("INVALID_ARGUMENT","Expected integer for --" + key,exitCode: 2) }
        return value
    }
    func budget() throws -> RunBudget {
        let scratch = try integer("scratch-mib",default: 512)
        guard (1...10240).contains(scratch) else { throw InvarError("INVALID_ARGUMENT","Scratch budget must be1...10240 MiB",exitCode: 2) }
        let budget = RunBudget(maximumWorkers: try integer("workers",default: 2),memoryMiB: try integer("memory-mib",default: 4096),timeoutSeconds: Double(try integer("timeout",default: 120)),runTimeoutSeconds: Double(try integer("run-timeout",default: 300)),maximumProcesses: try integer("processes",default: 8),maximumCPUSeconds: Double(try integer("cpu-seconds",default: 120)),maximumWorkspaceBytes: scratch * 1024 * 1024)
        try PlanValidation.budget(budget)
        return budget
    }
}
