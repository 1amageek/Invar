import Foundation

public struct VerificationConfiguration: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let architecture: [ArchitecturePolicy]
    public let native: [NativeCheck]
    public let fuzz: [FuzzCheck]
    public let project: ProjectCheck?
    public let formal: [FormalCheck]
    public init(schemaVersion: Int = 1, architecture: [ArchitecturePolicy] = [], formal: [FormalCheck] = [], native: [NativeCheck] = [], fuzz: [FuzzCheck] = [], project: ProjectCheck? = nil) {
        self.project = project
        self.schemaVersion = schemaVersion
        self.architecture = architecture
        self.formal = formal
        self.native = native
        self.fuzz = fuzz
    }
    public func identity() throws -> String {
        let ordered = VerificationConfiguration(schemaVersion: schemaVersion, architecture: architecture.sorted { $0.id < $1.id }, formal: formal.sorted { $0.id < $1.id }, native: native.sorted { $0.id < $1.id }, fuzz: fuzz.sorted { $0.id < $1.id }, project: project)
        return try Canonical.identity(ordered)
    }

}
