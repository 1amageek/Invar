import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import Darwin
import Foundation
import VerificationCore

public actor ExplorerProviderConnection: ExplorerConnecting, ProjectArchitectureReading {
    public nonisolated let actionLedger: ProviderActionLedger
    private let workspace: String
    private let manifest: ExtensionManifest
    private let credentialPath: URL
    private var resumeCredential: String?
    private var session: ExtensionProviderClient?
    private var pendingCleanup: ExtensionProviderClient?
    private var health = ExplorerConnectionStatus(state: .sourceOffline)
    private var pump: Task<Void,Never>?
    private var stopped = false
    private var closing = false
    public init(workspace: String,stateDirectory: URL,manifest: ExtensionManifest) throws {
        self.workspace = workspace; self.manifest = manifest
        credentialPath = stateDirectory.appendingPathComponent("explorer-resume.json")
        // This receipt owner must exist before any registration can deliver work.
        actionLedger = try ProviderActionLedger(path: stateDirectory.appendingPathComponent("provider-actions.json"))
        if FileManager.default.fileExists(atPath: credentialPath.path) {
            var info = stat()
            guard lstat(credentialPath.path,&info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_size <= 4096 else { throw InvarError("AUTHENTICATION_REQUIRED","Unsafe Explorer resume credential",exitCode: 8) }
            let bytes = try Data(contentsOf: credentialPath)
            let record = try JSONDecoder().decode([String:String].self,from: bytes)
            let manifestBytes = try CanonicalJSON.encode(manifest)
            let digest = CanonicalJSON.digest(manifestBytes)
            guard let recordedDigest = record["manifestDigest"], recordedDigest.utf8.count == 64,
                  recordedDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  let credential = record["credential"], (32...256).contains(credential.utf8.count) else {
                throw InvarError("AUTHENTICATION_REQUIRED","Invalid Explorer resume record",exitCode: 8)
            }
            if recordedDigest == digest { resumeCredential = credential }
        }
    }
    public func start() async throws -> ExplorerConnectionStatus {
        guard !stopped, !closing, pump == nil else { throw InvarError("INVALID_TRANSITION","Explorer connection is already started or closed") }
        await connect()
        pump = Task { await self.maintain() }
        return health
    }
    private func maintain() async {
        while !Task.isCancelled, !closing {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            if let session {
                do { try await session.heartbeat() }
                catch { self.session = nil; health = Self.failure(error) }
            } else { await connect() }
        }
    }
    private func connect() async {
        guard !closing, !stopped, pendingCleanup == nil else { return }
        do {
            let value = try await ExtensionProviderClient.register(workspace: workspace,manifest: manifest,resumeCredential: resumeCredential)
            pendingCleanup = value
            do {
                guard !closing, !stopped else { throw CancellationError() }
                _ = try AuthenticatedExplorerInputs(provider: value)
                let manifestBytes = try CanonicalJSON.encode(manifest)
                let record = try Canonical.encode(["manifestDigest":CanonicalJSON.digest(manifestBytes),"credential":value.registration.resumeCredential])
                try record.write(to: credentialPath,options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: credentialPath.path)
                let handle = try FileHandle(forWritingTo: credentialPath)
                do { try handle.synchronize(); try handle.close() }
                catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Resume record sync failed (\(error)); close failed (\(cleanup))") }; throw error }
                session = value; pendingCleanup = nil
                resumeCredential = value.registration.resumeCredential; health = ExplorerConnectionStatus(state: .ready)
            } catch {
                let original = error
                do { try await value.disconnect(); pendingCleanup = nil }
                catch { throw InvarError("CLEANUP_FAILED","Provider initialization failed (\(original)); session disconnect failed (\(error))",exitCode: 6) }
                throw original
            }
        } catch { health = Self.failure(error) }
    }
    private static func failure(_ error: any Error) -> ExplorerConnectionStatus {
        let value: InvarError
        if let error = error as? ArchitectureError { value = InvarError(error.code,error.message,exitCode: error.exitCode) }
        else { value = error as? InvarError ?? InvarError("SOURCE_OFFLINE",String(describing: error),exitCode: 6) }
        let bounded = InvarError(String(value.code.prefix(128)),String(value.message.prefix(1024)),exitCode: value.exitCode)
        return ExplorerConnectionStatus(state: ["APPROVAL_REQUIRED","POLICY_DENIED","PERMISSION_DENIED","AUTHENTICATION_REQUIRED"].contains(value.code) ? .approvalRequired : .sourceOffline,failure: bounded)
    }
    public func status() -> ExplorerConnectionStatus { health }
    public func provider() throws -> ExtensionProviderClient {
        guard !closing, !stopped, let session else { throw health.failure ?? InvarError("SOURCE_OFFLINE","Explorer Provider session is unavailable",exitCode: 6) }
        return session
    }
    public func capture() async throws -> CapturedWorkspace {
        let session = try provider(), inputs = try AuthenticatedExplorerInputs(provider: session)
        return try await ExplorerSnapshotReader(client: inputs).capture()
    }
    public func captureProject(snapshotID: String?,entityID: String) async throws -> CapturedWorkspace {
        let provider = try provider(), inputs = try AuthenticatedExplorerInputs(provider: provider)
        let reader = ExplorerProjectReader(client: inputs) { snapshot in
            let response = try await provider.client.call("graph.neighbors",parameters: .object(["focus":.string(entityID),"snapshotID":.string(snapshot),"depth":.number(0),"limit":.number(1)]))
            guard response["snapshotID"].string == snapshot, let record = response["nodes"].array.first(where: { $0["id"].string == entityID }) else { throw InvarError("INPUT_MISMATCH","Project subject is absent from its original snapshot") }
            return try record.decode(Entity.self)
        }
        return try await reader.capture(snapshotID: snapshotID)
    }
    public func closeAdmission() async {
        closing = true
        pump?.cancel(); await pump?.value; pump = nil
    }
    public func shutdown() async throws {
        if stopped { return }
        await closeAdmission()
        await actionLedger.shutdown()
        if let session { try await session.disconnect(); self.session = nil }
        if let pendingCleanup { try await pendingCleanup.disconnect(); self.pendingCleanup = nil }
        stopped = true
    }
}
