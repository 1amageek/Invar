public struct ExternalAdmission: Sendable {
    public let actionID: String
    public let receipt: OperationReceipt
    public init(actionID: String,receipt: OperationReceipt) { self.actionID = actionID; self.receipt = receipt }
}
