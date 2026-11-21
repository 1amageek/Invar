import Darwin
import Foundation
import ArchitectureCore
import InvarMap
import VerificationCore
import VerificationBackends
import VerificationRuntime
import VerificationDiscovery
import FormalValidation
import FormalCore

@main
struct InvarApp {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        ProcessSignals.install()
        let invocation = Task { await execute(arguments) }
        let signals = Task {
            while !Task.isCancelled {
                if ProcessSignals.interrupted { invocation.cancel(); return }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
        let code = await invocation.value
        signals.cancel(); await signals.value
        exit(ProcessSignals.interrupted ? 130 : code)
    }
    static func executableURL() throws -> URL {
        guard let executable = Bundle.main.executableURL else {
            throw InvarError("EXECUTOR_UNAVAILABLE", "Cannot locate the running executable")
        }
        return executable.resolvingSymlinksInPath()
    }

    private static func execute(_ arguments: [String]) async -> Int32 {
        var code: Int32 = 0
        do {
            if arguments.first == "map" {
                try MapCommand.run(Array(arguments.dropFirst()))
                return 0
            }
            let command = arguments.first
            if command == "--help" || command == "help" {
                print("""
                invar [--workspace PATH] [--policy PATH] [--no-open | --codex-browser]
                invar status | stop [--workspace PATH]
                invar mcp [--workspace PATH]
                invar daemon start | status | stop | approve | identity [--workspace PATH]
                invar capabilities | map | plan | run | report
                """)
                return 0
            }
            if command == nil || command?.hasPrefix("--workspace") == true ||
                ["--policy", "--state", "--no-open", "--codex-browser", "--contracts"].contains(command ?? "") || command == "open" {
                try await WorkspaceCommand.open(command == "open" ? Array(arguments.dropFirst()) : arguments)
                return 0
            }
            if let command, ["daemon", "status", "stop"].contains(command) {
                let options = command == "daemon" ? Array(arguments.dropFirst()) : arguments
                let data = try await DaemonCommand(options).execute()
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10])); return 0
            }
            if command == "mcp" {
                let options = try CommandOptions(arguments)
                try await WorkspaceCommand.activateForMCP(options)
                try await InvarMCP.run(options: options)
                return 0
            }
            let data: Data
            if let mode = arguments.first, ["--internal-worker", "--internal-native-build", "--internal-native-verify"].contains(mode) {
                guard arguments.count == 2 else { throw InvarError("INVALID_ARGUMENT", "Invalid worker invocation", exitCode: 2) }
                data = try await WorkerCommand.execute(mode: mode, input: arguments[1])
            } else {
                let result = try await CommandDriver(options: CommandOptions(arguments)).execute()
                data = result.0; code = result.1
            }
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        } catch {
            if let delivery = error as? OperationDeliveryError {
                do { FileHandle.standardOutput.write(try Canonical.encode(delivery)); FileHandle.standardOutput.write(Data([10])) }
                catch { FileHandle.standardError.write(Data("Cannot encode original prepared operation\n".utf8)) }
                return delivery.cause.exitCode
            }
            if let observation = error as? CommandObservationError {
                do { FileHandle.standardOutput.write(try Canonical.encode(observation)); FileHandle.standardOutput.write(Data([10])) }
                catch { FileHandle.standardError.write(Data("Cannot encode original operation receipt\n".utf8)) }
                return observation.cause.exitCode
            }
            let failure: InvarError
            if let typed = error as? InvarError { failure = typed }
            else if let typed = error as? ArchitectureError { failure = InvarError(typed.code, typed.message, exitCode: typed.exitCode) }
            else if let typed = error as? ToolResourceLimit { failure = InvarError("RESOURCE_LIMIT", typed.description, exitCode: 6) }
            else if let typed = error as? FormalDiagnostic { failure = InvarError(typed.code.rawValue, typed.message, exitCode: typed.exitCode) }
            else if error is DecodingError { failure = InvarError("INVALID_SCHEMA", String(describing: error), exitCode: 2) }
            else if error is CancellationError { failure = InvarError("CANCELLED", "Request cancelled", exitCode: 130) }
            else { failure = InvarError("EXECUTION_FAILED", String(describing: error), exitCode: 7) }
            do {
                let destination = ["mcp", "map"].contains(CommandLine.arguments.dropFirst().first ?? "") ? FileHandle.standardError : FileHandle.standardOutput
                destination.write(try Canonical.encode(failure)); destination.write(Data([10]))
            }
            catch { FileHandle.standardError.write(Data("Cannot encode command failure\n".utf8)) }
            code = failure.exitCode
        }
        return code
    }
}
