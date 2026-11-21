import ArchitectureClient
import ArchitectureCore
import Darwin
import Foundation
import VerificationCore

struct ExplorerHost {
    let executable: URL
    let workspace: URL

    static func locate(workspace: URL) throws -> Self {
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["INVAR_EXPLORER"] {
            guard configured.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: configured) else {
                throw InvarError("EXPLORER_UNAVAILABLE", "INVAR_EXPLORER must name an absolute executable path", exitCode: 3)
            }
            return Self(executable: URL(fileURLWithPath: configured).resolvingSymlinksInPath(), workspace: workspace)
        }
        let ownPath = try InvarApp.executableURL()
        let installed = ownPath.deletingLastPathComponent().appendingPathComponent("architecture")
        let directories = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }
        let candidates = [installed] + directories.map { URL(fileURLWithPath: String($0)).appendingPathComponent("architecture") }
        for candidate in candidates {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard !resolved.path.hasPrefix(workspace.path + "/"), FileManager.default.isExecutableFile(atPath: resolved.path) else { continue }
            return Self(executable: resolved, workspace: workspace)
        }
        throw InvarError("EXPLORER_UNAVAILABLE", "Install the paired Architecture Explorer commands on PATH, or set INVAR_EXPLORER to the paired CLI", exitCode: 3)
    }

    static func isIndexRunning(in workspace: URL) async throws -> Bool {
        let client = try ArchitectureClient(workspace: workspace.path)
        do { _ = try await client.call("daemon.hello"); return true }
        catch let error as ArchitectureError where error.code == "CONNECTION_FAILED" { return false }
    }

    func ensureIndex() async throws {
        if try await Self.isIndexRunning(in: workspace) { return }
        try await run(["daemon", "start"], timeout: .seconds(15), output: .standardError)
    }

    func open(noOpen: Bool, codexBrowser: Bool) async throws {
        let browser = noOpen ? ["--no-open"] : codexBrowser ? ["--codex-browser"] : []
        try await run(["explore", "--watch"] + browser, timeout: nil, output: .standardOutput)
    }

    private func run(_ arguments: [String], timeout: Duration?, output: FileHandle) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments + ["--workspace", workspace.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let deadline = timeout.map { ContinuousClock.now.advanced(by: $0) }
        do {
            while process.isRunning {
                try await Task.sleep(for: .milliseconds(50))
                if let deadline, ContinuousClock.now >= deadline {
                    throw InvarError("EXPLORER_TIMEOUT", "Explorer did not acknowledge index startup", exitCode: 6)
                }
            }
        } catch {
            if process.isRunning {
                process.terminate()
                await withTaskCancellationShield {
                    let grace = ContinuousClock.now.advanced(by: .seconds(3))
                    while process.isRunning && ContinuousClock.now < grace {
                        do { try await Task.sleep(for: .milliseconds(50)) } catch { await Task.yield() }
                    }
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            }
            throw error
        }
        guard process.terminationStatus == 0 else {
            throw InvarError("EXPLORER_START_FAILED", "Architecture Explorer exited with status \(process.terminationStatus)", exitCode: 7)
        }
    }
}
