import Foundation

public struct NativeProfile: Codable, Sendable, Equatable {
    public let kind: String
    public let compiler: String
    public let sdk: String
    public let toolsDirectory: String
    public let target: String
    public let modules: [NativeModule]
    public let harness: [String]
    public init(kind: String = "swift-modules-json/1", compiler: String, sdk: String, toolsDirectory: String, target: String = "arm64-apple-macosx27.0", modules: [NativeModule], harness: [String]) {
        self.kind = kind; self.compiler = compiler; self.sdk = sdk; self.toolsDirectory = toolsDirectory; self.target = target; self.modules = modules; self.harness = harness
    }
}
