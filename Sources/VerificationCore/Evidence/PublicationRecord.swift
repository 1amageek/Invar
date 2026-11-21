import Foundation

/// Immutable delivery state; opaque bytes belong to the authorized publication adapter.
public struct PublicationRecord: Codable, Sendable, Equatable {
    public let id: String
    public let runRequestID: String
    public let revision: Int
    public let entityID: String?
    public let providerID: String
    public let input: VerificationInput
    public let bindingDigest: String
    public let slot: String?
    public let generation: Int?
    public let handle: Data?
    public let view: ViewReference?
    public let payload: Data?
    public let completion: String?
    public let state: String
    public let failure: InvarError?
    public init(id: String,runRequestID: String? = nil,entityID: String? = nil,revision: Int = 1,providerID: String,input: VerificationInput,bindingDigest: String,slot: String? = nil,generation: Int? = nil,handle: Data? = nil,view: ViewReference? = nil,payload: Data? = nil,completion: String? = nil,state: String = "reserving",failure: InvarError? = nil) {
        self.entityID = entityID; self.id = id; self.runRequestID = runRequestID ?? id; self.revision = revision; self.providerID = providerID; self.input = input; self.bindingDigest = bindingDigest
        self.slot = slot; self.generation = generation; self.handle = handle; self.view = view; self.payload = payload; self.completion = completion; self.state = state; self.failure = failure
    }
    public func revising(state: String,slot: String? = nil,generation: Int? = nil,handle: Data? = nil,view: ViewReference? = nil,payload: Data? = nil,completion: String? = nil,failure: InvarError? = nil) -> Self {
        Self(id: id,runRequestID: runRequestID,entityID: entityID,revision: revision+1,providerID: providerID,input: input,bindingDigest: bindingDigest,slot: slot ?? self.slot,generation: generation ?? self.generation,handle: handle ?? self.handle,view: view ?? self.view,payload: payload ?? self.payload,completion: completion ?? self.completion,state: state,failure: failure)
    }
}
