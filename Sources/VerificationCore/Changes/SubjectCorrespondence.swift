import Foundation

public struct SubjectCorrespondence: Codable, Sendable, Equatable {
    public let before: SubjectReference
    public let after: SubjectReference
    public let producer: String
    public let basis: String
    public let precision: String
    public init(before: SubjectReference, after: SubjectReference, producer: String, basis: String, precision: String) {
        self.before = before
        self.after = after
        self.producer = producer
        self.basis = basis
        self.precision = precision
    }
}
