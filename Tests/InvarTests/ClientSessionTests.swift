import ArchitectureCore
import Darwin
import Foundation
import Testing
import VerificationClient
import VerificationCore
import VerificationDaemon

@Suite(.timeLimit(.minutes(1))) struct ClientSessionTests {
    actor Server: DaemonRequestHandling {
        let workspace = "workspace", epoch = UUID().uuidString
        let credential = UUID().uuidString + UUID().uuidString
        let resume = UUID().uuidString + UUID().uuidString
        var dropAcceptance = false, blockStatus = false, blockRenewal = false
        var openings = 0, acceptances = 0, statusReads = 0
        var auditIdentity: String?
        var granted: [WorkspaceCapability] = []
        var envelopes: [String:RequestEnvelope] = [:]
        var receipts: [String:OperationReceipt] = [:]
        init(dropAcceptance: Bool = false,blockStatus: Bool = false) { self.dropAcceptance = dropAcceptance; self.blockStatus = blockStatus }
        func holdRenewal() { blockRenewal = true }
        func handle(_ request: JSONValue,peer: ConnectionPeer,channel: DaemonRPCChannel) async throws -> JSONValue? {
            guard request["protocolVersion"].int == 2, request["workspaceID"].string == workspace else { throw InvarError("PROTOCOL_MISMATCH","Wrong fixture workspace/protocol") }
            let result: JSONValue, body = request["body"]
            if request["method"].string == "session.open" {
                openings += 1
                if openings > 1, blockRenewal { try await Task.sleep(for: .seconds(30)) }
                auditIdentity = peer.auditIdentity
                let desired = Set(body["capabilities"].array.compactMap(\.string))
                granted = desired.intersection(["read","verification"]).compactMap(WorkspaceCapability.init(rawValue:))
                let session = AgentSession(id: "session",principal: "authenticated-principal",agentLabel: body["label"].string,grants: desired.intersection(["read","verification"]).sorted(),policyRevision: 1,expiresAt: Date().timeIntervalSince1970 + 60)
                result = try JSONValue.encode(ClientSessionGrant(workspaceID: workspace,epoch: epoch,engineIdentity: String(repeating: "0",count: 64),session: session,credential: credential,resumeCredential: resume))
            } else {
                guard request["credential"].string == credential, request["epoch"].string == epoch, peer.auditIdentity == auditIdentity else { throw InvarError("AUTHENTICATION_REQUIRED","Credential is not bound to this actual peer") }
                switch request["method"].string {
                case "request.prepare":
                    let operation = try body["operation"].decode(WorkspaceOperation.self)
                    let key = try #require(body["key"].string)
                    let value: RequestEnvelope
                    if let existing = envelopes[key] { value = existing }
                    else {
                        let now = Date().timeIntervalSince1970
                        value = RequestEnvelope(id: UUID().uuidString,sessionID: "session",capabilities: granted,requestKey: key,principal: "authenticated-principal",workspaceID: workspace,fingerprint: try Canonical.identity(operation),operation: operation.name,daemonEpoch: epoch,policyRevision: 1,expiresAt: now+20,retainUntil: now+60)
                        envelopes[key] = value
                    }
                    result = try JSONValue.encode(value)
                case "request.accept":
                    let prepared = try body.decode(PreparedOperation.self)
                    let value: OperationReceipt
                    if let existing = receipts[prepared.envelope.id] { value = existing }
                    else {
                        acceptances += 1
                        value = OperationReceipt(id: prepared.envelope.id,operationID: "durable-operation",fingerprint: prepared.envelope.fingerprint,acceptedAt: Date().timeIntervalSince1970,daemonEpoch: epoch)
                        receipts[prepared.envelope.id] = value
                    }
                    if dropAcceptance { return nil }
                    result = try JSONValue.encode(value)
                case "query":
                    let query = try body.decode(WorkspaceQuery.self)
                    switch query {
                    case .receipt(let id): result = try JSONValue.encode(receipts[id])
                    case .status:
                        statusReads += 1
                        if blockStatus { try await Task.sleep(for: .seconds(30)) }
                        result = try JSONValue.encode(DaemonStatus(workspaceID: workspace,epoch: epoch,engineIdentity: String(repeating: "0",count: 64),policyRevision: 1,state: "ready",activeOperations: 0,watchCount: 0,diagnostics: []))
                    default: throw InvarError("UNSUPPORTED_OPERATION","Fixture query is outside the transport test")
                    }
                default: throw InvarError("METHOD_NOT_FOUND","Unknown fixture method")
                }
            }
            return result
        }
    }
    func root() throws -> URL {
        let path = URL(fileURLWithPath: "/tmp/invar-client-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: path,withIntermediateDirectories: false,attributes: [.posixPermissions: 0o700]); return path
    }
    @Test func actualSocketChecksServerBeforeSendingSecretsAndBindsSessionGrants() async throws {
        let root = try root(), path = root.appendingPathComponent("daemon.sock").path
        let server = Server()
        let transport = try DaemonRPCServer(socket: URL(fileURLWithPath: path),channel: .control,maximumConnections: 8,handler: server)
        let serving = Task { try await transport.serve() }
        defer {
            do { try await transport.shutdown() } catch { Issue.record(error) }
            serving.cancel()
            do { try await serving.value } catch is CancellationError {} catch { Issue.record(error) }
            do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        let peer = try ConnectionPeer.current()
        let wrong = LocalDaemonEndpoint(workspaceID: "workspace",socketPath: path,serverBinaryDigest: String(repeating: "f",count: 64),serverCodeIdentity: peer.codeIdentity,engineIdentity: String(repeating: "0",count: 64))
        await #expect(throws: InvarError.self) { try await LocalVerificationClient.connect(endpoint: wrong,capabilities: [.read]) }
        #expect(await server.openings == 0)
        let wrongCode = LocalDaemonEndpoint(workspaceID: "workspace",socketPath: path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: "another-signed-code-identity",engineIdentity: String(repeating: "0",count: 64))
        await #expect(throws: InvarError.self) { try await LocalVerificationClient.connect(endpoint: wrongCode,capabilities: [.read]) }
        #expect(await server.openings == 0)
        let wrongEngine = LocalDaemonEndpoint(workspaceID: "workspace",socketPath: path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: String(repeating: "1",count: 64))
        await #expect(throws: InvarError.self) { try await LocalVerificationClient.connect(endpoint: wrongEngine,capabilities: [.read]) }
        #expect(await server.acceptances == 0)
        let endpoint = LocalDaemonEndpoint(workspaceID: "workspace",socketPath: path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: String(repeating: "0",count: 64))
        let client = try await LocalVerificationClient.connect(endpoint: endpoint,label: "descriptive only",capabilities: [.read,.verification,.nativeExecution])
        #expect(try await client.session().grants == ["read","verification"])
        #expect(try await client.status().state == "ready")
        let receipt = try await client.verify(planID: String(repeating: "1",count: 64),changeRevisionID: nil,replayOfRunID: nil,key: "once",timeout: 20)
        #expect(try await client.receipt(envelopeID: receipt.id) == receipt)
        #expect(await server.acceptances == 1)
        await client.shutdown()
        await #expect(throws: InvarError.self) { try await client.status() }
    }
    @Test func lostAcceptanceAckPreservesFixedEnvelopeAndDoesNotResubmit() async throws {
        let root = try root(), path = root.appendingPathComponent("daemon.sock").path
        let server = Server(dropAcceptance: true)
        let transport = try DaemonRPCServer(socket: URL(fileURLWithPath: path),channel: .control,maximumConnections: 8,handler: server)
        let serving = Task { try await transport.serve() }
        defer {
            do { try await transport.shutdown() } catch { Issue.record(error) }
            serving.cancel()
            do { try await serving.value } catch is CancellationError {} catch { Issue.record(error) }
            do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        let peer = try ConnectionPeer.current(), endpoint = LocalDaemonEndpoint(workspaceID: "workspace",socketPath: path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: String(repeating: "0",count: 64))
        let client = try await LocalVerificationClient.connect(endpoint: endpoint,capabilities: [.read,.verification])
        let operation = WorkspaceOperation.verify(planID: String(repeating: "1",count: 64),changeRevisionID: nil,replayOfRunID: nil)
        let prepared = try await client.prepare(operation,key: "fixed",timeout: 20)
        do { _ = try await client.accept(prepared); Issue.record("Lost ACK became success") }
        catch let error as OperationDeliveryError { #expect(error.prepared == prepared) }
        let receipt = try #require(try await client.receipt(envelopeID: prepared.envelope.id))
        #expect(receipt.id == prepared.envelope.id); #expect(await server.acceptances == 1)
        await client.shutdown()
    }
    @Test func shutdownDrainsAnOwnedPendingSocketCall() async throws {
        let root = try root(), path = root.appendingPathComponent("daemon.sock").path
        let server = Server(blockStatus: true)
        let transport = try DaemonRPCServer(socket: URL(fileURLWithPath: path),channel: .control,maximumConnections: 8,handler: server)
        let serving = Task { try await transport.serve() }
        defer {
            do { try await transport.shutdown() } catch { Issue.record(error) }
            serving.cancel()
            do { try await serving.value } catch is CancellationError {} catch { Issue.record(error) }
            do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        let peer = try ConnectionPeer.current(), endpoint = LocalDaemonEndpoint(workspaceID: "workspace",socketPath: path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: String(repeating: "0",count: 64))
        let client = try await LocalVerificationClient.connect(endpoint: endpoint,capabilities: [.read])
        let call = Task { try await client.status() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await server.statusReads == 0 {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Socket query did not start") }
            try await Task.sleep(for: .milliseconds(2))
        }
        await client.shutdown()
        do { _ = try await call.value; Issue.record("Closed pending call became success") } catch { #expect(error is InvarError) }
    }
    @Test func shutdownDrainsAnOwnedPendingSessionRenewalWithoutRestoringClosedCredentials() async throws {
        let root = try root(), path = root.appendingPathComponent("daemon.sock").path, server = Server()
        let transport = try DaemonRPCServer(socket: URL(fileURLWithPath: path),channel: .control,maximumConnections: 8,handler: server)
        let serving = Task { try await transport.serve() }
        defer {
            do { try await transport.shutdown() } catch { Issue.record(error) }
            serving.cancel()
            do { try await serving.value } catch is CancellationError {} catch { Issue.record(error) }
            do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        let peer = try ConnectionPeer.current()
        let endpoint = LocalDaemonEndpoint(workspaceID: "workspace",socketPath: path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: String(repeating: "0",count: 64))
        let client = try await LocalVerificationClient.connect(endpoint: endpoint,capabilities: [.read])
        await server.holdRenewal()
        let renewal = Task { try await client.refreshSession() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await server.openings < 2 {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Session renewal did not reach the socket handler") }
            try await Task.sleep(for: .milliseconds(2))
        }
        let start = ContinuousClock.now
        await client.shutdown()
        #expect(start.duration(to: .now) < .seconds(1))
        do { _ = try await renewal.value; Issue.record("Closed client restored a renewed session") }
        catch is InvarError {}
        await #expect(throws: InvarError.self) { try await client.session() }
    }

}
