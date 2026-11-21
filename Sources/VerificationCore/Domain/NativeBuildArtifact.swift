import Foundation

public struct NativeBuildArtifact: Codable, Sendable, Equatable {
    public let planID: String
    public let jobID: String
    public let binary: URL
    public let binaryDigest: String
    public let environmentIdentity: String
    public let resources: [String: Double]
    public init(planID: String, jobID: String, binary: URL, binaryDigest: String, environmentIdentity: String, resources: [String: Double] = [:]) {
        self.planID = planID; self.jobID = jobID; self.binary = binary; self.binaryDigest = binaryDigest; self.environmentIdentity = environmentIdentity; self.resources = resources
    }
}
