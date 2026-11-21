import ArchitectureExtensions

/// Proves that rebinding cannot create a replacement generation for lost work.
public protocol OriginalPublicationChecking: Sendable {
    func requireOriginalRun(_ run: ExtensionRun) async throws
}
