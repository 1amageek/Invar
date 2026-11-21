import ArchitectureClient
import ArchitectureCore
import Darwin
import Foundation
import VerificationCore

struct ExplorerHost {
    let executable: URL
    let workspace: URL

    static func locate(workspace: URL) throws -> Self {
        let bundle = try InvarApp.executableURL().deletingLastPathComponent().appendingPathComponent("Invar_invar.bundle")
        guard let host = Bundle(url: bundle)?.url(forResource: "architecture-host", withExtension: nil),
              FileManager.default.isExecutableFile(atPath: host.path) else {
            throw InvarError("EXPLORER_UNAVAILABLE", "The Invar installation is missing its bundled Explorer host", exitCode: 3)
        }
        return Self(executable: host, workspace: workspace)
    }

    static func isIndexRunning(in workspace: URL) async throws -> Bool {
        let client = try ArchitectureClient(workspace: workspace.path)
        do { _ = try await client.call("daemon.hello"); return true }
        catch let error as ArchitectureError where error.code == "CONNECTION_FAILED" { return false }
    }

    func ensureIndex() async throws {
        try await run(["start"], timeout: .seconds(25), output: .standardError)
    }

    func open(noOpen: Bool, codexBrowser: Bool) async throws {
        let browser = noOpen ? ["--no-open"] : codexBrowser ? ["--codex-browser"] : []
        try await run(["browser"] + browser, timeout: nil, output: .standardOutput)
    }

    private func run(_ arguments: [String], timeout: Duration?, output: FileHandle) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = [arguments[0], "--workspace", workspace.path] + arguments.dropFirst()
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
