import ArchitectureCore
import Darwin
import Foundation
import VerificationClient
import VerificationCore
import VerificationDaemon

struct DaemonLauncher {
    func start(configuration: DaemonConfiguration,engineIdentity: String,policyPath: String?) async throws -> DaemonStatus {
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        defer { await admin.shutdown() }
        do {
            let status = try await admin.status(), endpoint = try await admin.endpoint()
            guard endpoint.engineIdentity == engineIdentity else { throw InvarError("EXECUTOR_MISMATCH","Explicitly stop the old engine before starting a replacement") }
            return status
        } catch let error as InvarError where ["DAEMON_UNAVAILABLE","AUTHENTICATION_REQUIRED"].contains(error.code) {
            // A private-record ownership failure is not permission to replace a
            // running owner; the child must still acquire the workspace lock.
        } catch let error as ArchitectureError where error.code == "CONNECTION_FAILED" {}
        let expectedBinary = try Data(contentsOf: configuration.executable,options: .mappedIfSafe)
        guard expectedBinary.count <= 128 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT","Configured daemon binary exceeds peer identity profile") }
        var arguments = ["daemon","serve","--workspace",configuration.workspace.path,"--state",configuration.paths.stateDirectory.path]
        if !configuration.explicitStart { arguments += ["--automatic", "true"] }
        if let path = policyPath { arguments += ["--policy",URL(fileURLWithPath: path).standardizedFileURL.path] }
        if let path = configuration.defaultConfigurationPath { arguments += ["--contracts",path] }
        let output = try bootstrapOutput()
        let pid = try spawn(configuration.executable,arguments: arguments,output: output.fileDescriptor)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var reaped = false
        do {
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                var status: Int32 = 0
                if !reaped {
                    let observed = waitpid(pid,&status,WNOHANG)
                    guard observed >= 0 else { throw InvarError("DAEMON_START_FAILED","Cannot observe newly launched daemon",exitCode: 7) }
                    if observed == pid {
                        reaped = true
                        try output.seek(toOffset: 0)
                        let bytes = try output.read(upToCount: 16_384) ?? Data()
                        let error: InvarError
                        do { error = try JSONDecoder().decode(InvarError.self, from: bytes) }
                        catch { throw InvarError("DAEMON_START_FAILED", "Daemon exited before its authenticated endpoint became ready (status \(status))", exitCode: 7) }
                        guard error.code == "DAEMON_ALREADY_RUNNING" else { throw error }
                    }
                }
                do {
                    let value = try await admin.status(), endpoint = try await admin.endpoint()
                    guard endpoint.serverBinaryDigest == Canonical.digest(expectedBinary), endpoint.engineIdentity == engineIdentity else { throw InvarError("EXECUTOR_MISMATCH","Started endpoint is not the configured daemon binary/engine") }
                    return value
                } catch let error as InvarError where ["DAEMON_UNAVAILABLE","AUTHENTICATION_REQUIRED"].contains(error.code) {}
                catch let error as ArchitectureError where error.code == "CONNECTION_FAILED" {}
                try await Task.sleep(for: .milliseconds(25))
            }
            throw InvarError("TIMEOUT","Daemon startup did not become observable within ten seconds",exitCode: 6)
        } catch {
            if !reaped { try await stopSpawned(pid) }
            throw error
        }
    }
    private func bootstrapOutput() throws -> FileHandle {
        // Redirect startup errors to an anonymous file. A detached child can
        // finish normally after the launcher has closed its descriptor.
        var name = Array(FileManager.default.temporaryDirectory.appendingPathComponent("invar-start.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&name)
        guard descriptor >= 0 else { throw InvarError("DAEMON_START_FAILED", "Cannot allocate private startup output", exitCode: 7) }
        guard unlink(&name) == 0, fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            close(descriptor)
            throw InvarError("DAEMON_START_FAILED", "Cannot make startup output anonymous", exitCode: 7)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func spawn(_ executable: URL,arguments: [String],output: Int32) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw InvarError("DAEMON_START_FAILED","Cannot create spawn actions") }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw InvarError("DAEMON_START_FAILED","Cannot create spawn attributes") }
        defer { posix_spawnattr_destroy(&attributes) }
        var mask = sigset_t(), defaults = sigset_t()
        sigemptyset(&mask); sigemptyset(&defaults)
        sigaddset(&defaults,SIGINT); sigaddset(&defaults,SIGTERM); sigaddset(&defaults,SIGHUP)
        guard posix_spawnattr_setsigmask(&attributes,&mask) == 0, posix_spawnattr_setsigdefault(&attributes,&defaults) == 0 else { throw InvarError("DAEMON_START_FAILED","Cannot reset inherited bootstrap signal state") }
        guard posix_spawn_file_actions_addopen(&actions,STDIN_FILENO,"/dev/null",O_RDONLY,0) == 0,
            posix_spawn_file_actions_adddup2(&actions,output,STDOUT_FILENO) == 0,
            posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,"/dev/null",O_WRONLY,0) == 0,
            posix_spawnattr_setflags(&attributes,Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)) == 0 else { throw InvarError("DAEMON_START_FAILED","Cannot configure detached daemon session") }
        let values = [executable.path] + arguments, environment = ProcessInfo.processInfo.environment.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }
        guard (values+environment).allSatisfy({ !$0.utf8.contains(0) }) else { throw InvarError("INVALID_ARGUMENT","NUL in daemon bootstrap arguments/environment") }
        // These owned C strings and terminated pointer arrays remain initialized
        // only through posix_spawn. No pointer escapes; every allocation is freed
        // exactly once by this scope. The detached daemon owns its own residency.
        var argv = values.map { strdup($0) }, envp = environment.map { strdup($0) }
        defer { for pointer in argv { free(pointer) }; for pointer in envp { free(pointer) } }
        guard argv.allSatisfy({ $0 != nil }), envp.allSatisfy({ $0 != nil }) else { throw InvarError("DAEMON_START_FAILED","Cannot allocate bootstrap arguments") }
        argv.append(nil); envp.append(nil)
        var pid: pid_t = 0
        let code = posix_spawn(&pid,executable.path,&actions,&attributes,&argv,&envp)
        guard code == 0 else { throw InvarError("DAEMON_START_FAILED","Cannot spawn configured daemon (\(code))",exitCode: 7) }
        return pid
    }
    private func stopSpawned(_ pid: pid_t) async throws {
        // The unreaped child PID cannot be recycled. This path only stops the
        // bootstrap child owned by this invocation, never an existing daemon.
        kill(pid,SIGTERM)
        let grace = ContinuousClock.now.advanced(by: .seconds(2)), deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while true {
            var status: Int32 = 0
            let result = waitpid(pid,&status,WNOHANG)
            if result == pid { return }
            guard result >= 0, ContinuousClock.now < deadline else { throw InvarError("CLEANUP_FAILED","Spawned daemon has not exited/reaped") }
            if ContinuousClock.now >= grace { kill(pid,SIGKILL) }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { await Task.yield() }
        }
    }
}
