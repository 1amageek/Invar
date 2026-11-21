public protocol ProjectArchitectureReading: ArchitectureReading {
    func captureProject(snapshotID: String?,entityID: String) async throws -> CapturedWorkspace
}
