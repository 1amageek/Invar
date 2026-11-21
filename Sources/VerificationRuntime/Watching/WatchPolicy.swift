import VerificationCore

public struct WatchPolicy: Sendable {
    public let pollSeconds: Double
    public let probeSeconds: Double
    public let retrySeconds: Double
    public let settleSeconds: Double
    public let maximumSettleSeconds: Double
    public let maximumConcurrentCycles: Int
    public init(pollSeconds: Double,probeSeconds: Double,retrySeconds: Double,settleSeconds: Double,maximumSettleSeconds: Double,maximumConcurrentCycles: Int) {
        self.pollSeconds = pollSeconds; self.probeSeconds = probeSeconds; self.retrySeconds = retrySeconds
        self.settleSeconds = settleSeconds; self.maximumSettleSeconds = maximumSettleSeconds; self.maximumConcurrentCycles = maximumConcurrentCycles
    }
    public static let development = WatchPolicy(pollSeconds: 0.5,probeSeconds: 3,retrySeconds: 5,settleSeconds: 0.25,maximumSettleSeconds: 1,maximumConcurrentCycles: 2)
    public func validate() throws {
        guard [pollSeconds,probeSeconds,retrySeconds,settleSeconds,maximumSettleSeconds].allSatisfy({ $0.isFinite }),
            (0.01...60).contains(pollSeconds), (0.01...3600).contains(probeSeconds), (0.01...3600).contains(retrySeconds),
            settleSeconds >= 0, maximumSettleSeconds >= settleSeconds, maximumSettleSeconds <= 60,
            (1...32).contains(maximumConcurrentCycles) else { throw InvarError("INVALID_POLICY","Invalid watch scheduling policy") }
    }
}
