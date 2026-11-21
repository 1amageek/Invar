import MCP

/// Describes original SDK query records without examples or embedded authority.
enum FormalQuerySchema {
    static var value: Value {
        let identity: Value = .object(["type":.string("string"),"pattern":.string("^[0-9a-f]{64}$")])
        let handle: Value = .object(["type":.string("string"),"minLength":.int(1),"maxLength":.int(128)])
        let budget = object([
            "maximumDatabaseBytes": integer(1),"maximumRecordBytes": integer(1,524288),"maximumPageBytes": integer(1,524288),
            "maximumNodes": integer(2,500),"maximumEdges": integer(1,1500),"maximumTraversalNodes": integer(1,1000000),"maximumCursors": integer(1,16)
        ])
        let reference = object(["id":identity,"sha256":identity,"byteCount":integer(1)])
        let graph = object([
            "graphID":identity,"roots":array(identity,15000),"relations":array(.object(["type":.string("string"),"maxLength":.int(256)]),1500),
            "direction":.object(["type":.string("string"),"enum":.array(["outgoing","incoming","both"].map(Value.string))]),"depth":integer(0,1000000)
        ],optional: ["cursor":.object(["type":.string("string"),"maxLength":.int(4096)])])
        let document = object(["documentID":identity,"start":integer(0),"count":integer(1,196608)])
        let origins = object(["documentID":identity,"start":integer(0),"count":integer(1,1500)])
        let trace = object(["traceID":identity,"start":integer(0),"count":integer(1,1500)])
        let variants: [String:Value] = [
            "open":object(["evidenceID":identity,"reference":reference,"budget":budget]),
            "catalog":object(["handle":handle]),"close":object(["handle":handle]),
            "graph":object(["handle":handle,"query":graph]),"trace":object(["handle":handle,"query":trace]),
            "origins":object(["handle":handle,"query":origins]),"document":object(["handle":handle,"query":document])
        ]
        return .object(["oneOf":.array(variants.keys.sorted().map { object([$0:variants[$0]!]) })])
    }
    private static func object(_ required: [String:Value],optional: [String:Value] = [:]) -> Value {
        .object(["type":.string("object"),"properties":.object(required.merging(optional) { first,_ in first }),"required":.array(required.keys.sorted().map(Value.string)),"additionalProperties":.bool(false)])
    }
    private static func integer(_ minimum: Int,_ maximum: Int? = nil) -> Value {
        var fields: [String:Value] = ["type":.string("integer"),"minimum":.int(minimum)]
        if let maximum { fields["maximum"] = .int(maximum) }
        return .object(fields)
    }
    private static func array(_ item: Value,_ maximum: Int) -> Value {
        .object(["type":.string("array"),"items":item,"maxItems":.int(maximum)])
    }
}
