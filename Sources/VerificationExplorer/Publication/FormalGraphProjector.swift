import ArchitectureCore
import ArchitectureExtensions
import FormalEvidence
import Foundation
import VerificationCore

public struct FormalGraphProjector: FormalGraphProjecting {
    private struct PageIdentity: Encodable {
        let graphID: String
        let nodes: [FormalNode]
        let edges: [FormalEdge]
        let frontier: [String]
        let selectionComplete: Bool
        let hasMorePages: Bool
        init(_ page: FormalGraphPage) {
            graphID = page.graphID; nodes = page.nodes; edges = page.edges; frontier = page.frontier
            selectionComplete = page.selectionComplete; hasMorePages = page.nextCursor != nil
        }
    }
    public init() {}
    public func project(_ page: FormalGraphPage,descriptor: FormalGraphDescriptor,query: FormalGraphQuery,context: FormalProjectionContext) throws -> FormalGraphProjection {
        guard descriptor.extraction == "available" else { throw InvarError("FORMAL_GRAPH_UNAVAILABLE","Extraction is unavailable; original verification axes remain unchanged",exitCode: 3) }
        let ids = Set(page.nodes.map(\.id))
        guard query.graphID == descriptor.id, query.roots.count <= 128, query.roots.allSatisfy(EvidenceIdentity.validID), query.relations.count <= 64,
            query.relations.allSatisfy({ $0.utf8.count <= 256 && !$0.utf8.contains(0) }), ["outgoing","incoming","both"].contains(query.direction), (0...1_000_000).contains(query.depth),
            page.graphID == descriptor.id, EvidenceIdentity.validID(descriptor.id), page.nodes.count <= 500, page.edges.count <= 1500,
            ids.count == page.nodes.count, page.nodes.allSatisfy({ EvidenceIdentity.validID($0.id) }), Set(page.edges.map(\.id)).count == page.edges.count,
            page.edges.allSatisfy({ EvidenceIdentity.validID($0.id) && ids.contains($0.source) && ids.contains($0.target) }),
            descriptor.roots.allSatisfy(EvidenceIdentity.validID), Set(descriptor.roots).count == descriptor.roots.count else { throw InvarError("INVALID_FORMAL_GRAPH","Formal page has invalid graph/root/endpoint identities") }
        // Cursor capabilities are per-reader state, not graph content identity.
        let pageBytes = try EvidenceIdentity.encode(PageIdentity(page)), descriptorBytes = try EvidenceIdentity.encode(descriptor)
        let scope = FormalGraphQuery(graphID: query.graphID,roots: query.roots,relations: query.relations,direction: query.direction,depth: query.depth)
        let queryBytes = try EvidenceIdentity.encode(scope), bindingBytes = try CanonicalJSON.encode(context.binding)
        let queryDigest = Canonical.digest(queryBytes), bindingDigest = Canonical.digest(bindingBytes)
        let pageDigest = Canonical.digest(pageBytes), descriptorDigest = Canonical.digest(descriptorBytes)
        func identity(_ original: String,_ kind: String) -> String { context.providerID + ":" + Canonical.parts("invar.formal-element/1",[context.bundle.id,descriptor.id,kind,original]) }
        let roots = Set(descriptor.roots)
        let language: String
        switch descriptor.kind { case .leanDeclarations,.leanProofTerm: language = "lean"; case .irControlFlow: language = "ir"; default: language = "tla" }
        let nodes: [JSONValue] = page.nodes.map { node in
            var attributes: [String:JSONValue] = ["formalNodeID":.string(node.id),"isDeclaredRoot":.bool(roots.contains(node.id)),"originRangeCount":.number(Double(node.ranges.count)),"stateValueAvailable":.bool(node.stateValue != nil),"stateValueIncluded":.bool(false)]
            for key in ["initial","kernelReplayed","bodyAvailable"] {
                if let text = node.attributes[key], ["true","false"].contains(text) { attributes[key] = .bool(text == "true") }
            }
            let documents = Set(node.ranges.map(\.documentID)).sorted()
            attributes["documentIDs"] = .array(documents.prefix(8).map(JSONValue.string))
            attributes["documentReferencesTruncated"] = .bool(documents.count > 8)
            var label = Self.label(node,kind: descriptor.kind)
            if descriptor.producer == "swift-formal/swift-expression-v1" {
                if ["No arithmetic trap","Possible trap","Always traps","Then branch","Else path","Predicate abstracted","Continue","Guard failure"].contains(node.label) {
                    label = node.label
                } else if node.kind == "action", node.label.wholeMatch(of: /L[0-9]+ · (If condition|Guard condition|(Int64 input|Collection count|-?[0-9]+) [*+%\/\-] (Int64 input|Collection count|-?[0-9]+))/) != nil,
                    let digest = descriptor.artifactDigests.last, EvidenceIdentity.validID(digest),
                    let range = node.ranges.first(where: { $0.documentID == EvidenceIdentity.id("source-document",digest,"swift") }) {
                    label = node.label
                    attributes["sourceStart"] = .number(Double(range.start))
                    attributes["sourceEnd"] = .number(Double(range.end))
                    attributes["sourceDigest"] = .string(digest)
                }
            }
            attributes["labelTruncated"] = .bool(label.count > 128)
            return .object(["id":.string(identity(node.id,"node")),"kind":.string(String(node.kind.prefix(128))),"language":.string(language),"label":.string(String(label.prefix(128))),"attributes":.object(attributes)])
        }
        let edges: [JSONValue] = page.edges.map { edge in
            .object(["id":.string(identity(edge.id,"edge")),"source":.string(identity(edge.source,"node")),"target":.string(identity(edge.target,"node")),"kind":.string(String(edge.kind.prefix(128))),"label":.string(String(edge.kind.prefix(128))),"attributes":.object(["formalEdgeID":.string(edge.id)])])
        }
        let publicRoots = descriptor.roots.prefix(128).map { identity($0,"node") }
        var metadata: [String:JSONValue] = [
            "pageDigest":.string(pageDigest),"descriptorDigest":.string(descriptorDigest),"queryDigest":.string(queryDigest),
            "selectedRoots":.array(query.roots.map { .string(identity($0,"node")) }),"direction":.string(query.direction),"depth":.number(Double(query.depth)),"relations":.array(query.relations.map(JSONValue.string)),"projectionProfile":.string("invar.formal-graph.structural/1"),
            "viewID":.string(context.view.id),"viewDigest":.string(context.view.sha256),"viewSequence":.number(Double(context.view.sequence)),
            "evidenceID":.string(context.evidence.evidenceID),"bundleID":.string(context.bundle.id),"formalGraphID":.string(descriptor.id),
            "formalKind":.string(descriptor.kind.rawValue),"producer":.string(String(descriptor.producer.prefix(256))),
            "scopeDigest":.string(Canonical.digest(Data(descriptor.scope.utf8))),"execution":.string(context.evidence.execution),
            "outcome":.string(context.evidence.outcome),"domain":.string(context.evidence.domain),"translation":.string(context.evidence.translation),
            "applicability":context.evidence.applicability.map(JSONValue.string) ?? .null,"adequacy":.string(context.evidence.adequacy),
            "upstreamDependencyStatus":.string(context.input.dependencyStatus),"extraction":.string(descriptor.extraction),
            "producerScopeComplete":.bool(descriptor.complete),"selectionComplete":.bool(page.selectionComplete),"pageComplete":.bool(page.nextCursor == nil),
            "frontierCount":.number(Double(page.frontier.count)),"hasMorePages":.bool(page.nextCursor != nil),
            "declaredRoots":.array(publicRoots.map(JSONValue.string)),"rootReferencesTruncated":.bool(descriptor.roots.count > 128),
            "sourceTextIncluded":.bool(false),"stateValuesIncluded":.bool(false),"sourceMapping":.string("Original document references; no inferred core-source link")
        ]
        if context.evidence.outcome == "notEvaluated", ["swift-formal/emitter","swift-formal/swift-expression-v1"].contains(descriptor.producer) {
            metadata["modelStatus"] = .string("generatedUnverified")
        }
        let body: JSONValue = .object(["nodes":.array(nodes),"edges":.array(edges),"metadata":.object(metadata)])
        let encoded = try CanonicalJSON.encode(body)
        let id = Canonical.parts("invar.formal-graph.structural/1",[context.view.sha256,context.bundle.sha256,descriptor.id,descriptorDigest,pageDigest,queryDigest,bindingDigest,CanonicalJSON.digest(encoded)])
        metadata["projectionID"] = .string(id)
        let data: JSONValue = .object(["nodes":.array(nodes),"edges":.array(edges),"metadata":.object(metadata)])
        let contribution = ExtensionContribution(id: context.providerID + ":formal-" + id,kind: "graph",binding: context.binding,data: data)
        let manifest = ExtensionManifest(extensionID: context.providerID,displayName: "Invar",requestedPermissions: [.graphRead,.graphsWrite,.runsWrite])
        try ExtensionRules.contribution(contribution,provider: manifest,binding: context.binding)
        return FormalGraphProjection(id: id,view: context.view,graphID: descriptor.id,bundleID: context.bundle.id,contribution: contribution)
    }
    private static func label(_ node: FormalNode,kind: FormalGraphKind) -> String {
        if node.kind == "state" {
            if let text = node.attributes["index"], let index = Int(text), (0..<Int.max).contains(index) { return "Step " + String(index+1) }
            return "State " + node.id.prefix(8)
        }
        if kind == .leanProofTerm { return node.kind + " " + node.id.prefix(8) }
        let named: Set<String> = ["module","moduleInstance","variable","constant","operator","action","invariant","theorem","lemma","definition","axiom","opaque","type","function","block"]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._'!?+-*/=<>∈∉⊆∪∩"))
        if named.contains(node.kind), !node.label.isEmpty, node.label.unicodeScalars.allSatisfy({ allowed.contains($0) }) { return node.label }
        return node.kind + " " + node.id.prefix(8)
    }
}
