import Foundation
import VerificationCore

public enum BoundedOperation {
    public static func run<Value: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        guard seconds.isFinite && seconds > 0 else { throw InvarError("TIMEOUT", "No deadline budget remains", exitCode: 6) }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: .seconds(seconds)); throw InvarError("TIMEOUT", "Operation exceeded its deadline", exitCode: 6) }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw InvarError("INCOMPLETE_OPERATION", "No operation completed") }
            return value
        }
    }
}
