import Foundation

public struct CapturedWorkspace: Codable, Sendable, Equatable {
    public let inventory: ScopeInventory
    public let files: [String: Data]
    public init(inventory: ScopeInventory, files: [String: Data]) {
        self.inventory = inventory
        self.files = files
    }
}
