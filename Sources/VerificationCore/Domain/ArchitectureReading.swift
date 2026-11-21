import Foundation

public protocol ArchitectureReading: Sendable {
    func capture() async throws -> CapturedWorkspace
}
