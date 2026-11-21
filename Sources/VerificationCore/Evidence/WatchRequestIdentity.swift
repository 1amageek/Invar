public enum WatchRequestIdentity {
    public static func envelopeID(watchID: String,generation: Int,operation: String) -> String {
        Canonical.parts("invar.watch-envelope/2",[watchID,String(generation),operation])
    }
    public static func demandID(watchID: String,generation: Int,operation: String) -> String {
        let envelope = envelopeID(watchID: watchID,generation: generation,operation: operation)
        return Canonical.parts("invar.operation/2",[envelope])
    }
    public static func key(watchID: String,generation: Int,operation: String) -> String { "watch-" + watchID + "-" + String(generation) + "-" + operation }
}
