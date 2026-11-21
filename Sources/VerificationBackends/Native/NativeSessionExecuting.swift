import FormalValidation

public protocol NativeSessionExecuting: ToolExecuting {
    func charge(_ resources: [String: Double]) async throws
    func summary() async throws -> [String: Double]
}
