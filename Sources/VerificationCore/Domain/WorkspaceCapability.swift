public enum WorkspaceCapability: String, Codable, Sendable, CaseIterable {
    case read, changes, planning, verification, watching, sourceValues, nativeExecution, userLeanExecution, administration
}
