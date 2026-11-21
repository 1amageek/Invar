import Foundation
import Testing
import VerificationClient
import VerificationCore

@Suite(.timeLimit(.minutes(1))) struct ClientSessionRenewalTests {
    @Test func concurrentCallsRenewExpiredSessionWithoutChangingPrincipalOrRepeatingAcceptedWork() async throws {
        let environment = try await DaemonProtocolTests().environment(sessionSeconds: 0.5)
        defer { do { try await environment.shutdown() } catch { Issue.record(error) } }
        let client = try await LocalVerificationClient.connect(endpoint: environment.endpoint,capabilities: [.read,.verification])
        defer { await client.shutdown() }
        let original = try await client.session()
        let receipt = try await client.verify(planID: environment.plan.id,changeRevisionID: nil,replayOfRunID: nil,key: "original-before-renewal",timeout: 15)
        let completed = try await DaemonProtocolTests().wait(receipt,client: client)
        let remaining = original.expiresAt-Date().timeIntervalSince1970
        if remaining > 0 { try await Task.sleep(for: .seconds(remaining+0.03)) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { _ = try await client.status() } }
            try await group.waitForAll()
        }
        let renewed = try await client.session()
        #expect(renewed.id != original.id && renewed.principal == original.principal && renewed.grants == original.grants)
        #expect(try await client.receipt(envelopeID: receipt.id) == receipt)
        #expect(try await client.operation(receipt.operationID) == completed)
        let explicit = try await client.refreshSession()
        #expect(explicit.id != renewed.id && explicit.principal == original.principal)
        await client.shutdown()
        await #expect(throws: InvarError.self) { try await client.refreshSession() }
    }
}
