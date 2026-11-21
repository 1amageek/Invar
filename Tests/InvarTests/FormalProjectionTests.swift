import ArchitectureCore
import ArchitectureExtensions
import FormalEvidence
import Foundation
import Testing
import VerificationCore
@testable import VerificationExplorer

@Suite(.timeLimit(.minutes(1))) struct FormalProjectionTests {
    private func id(_ name: String) -> String { EvidenceIdentity.id("projection-test",name) }
    private func context(bundle: EvidenceArtifactReference? = nil,manifestDigest: String? = nil) throws -> FormalProjectionContext {
        let input = try VerificationInput.reference(DomainTests.inventory())
        let artifact = bundle ?? EvidenceArtifactReference(id: id("bundle"),sha256: id("bytes"),byteCount: 100,mediaType: "application/vnd.formal.evidence.sqlite",profile: "formal-evidence/1")
        let evidence = VerificationEvidence(inputID: input.id,jobID: "formal",execution: "completed",outcome: "violated",domain: "generatedModel",translation: "unvalidated",scope: "Finite fixture",adequacy: "unknown",detail: "Fixture",artifacts: [artifact],startedAt: "start",finishedAt: "finish")
        let association = EvidenceAssociation.make(evidence: evidence,changeRevisionID: nil,input: input,status: "stale",basis: "Fixture",unknownBoundaries: ["Upstream unknown"],reuseDecision: "originalExecution")
        let view = ChangeVerificationView(workspaceID: input.workspaceID,changeRevisionID: nil,input: input,daemonEpoch: "epoch",sequence: 1,delta: nil,impactEntityIDs: [],unknownBoundaries: ["Upstream unknown"],planIDs: [],runIDs: [],evidenceIDs: [evidence.id],associations: [association],pendingDemandIDs: [],diagnostics: [])
        let binding = ExtensionBinding(workspaceID: input.workspaceID,snapshotID: input.snapshotID,inputManifestDigest: manifestDigest ?? id("original-manifest"))
        return try FormalProjectionContext(view: view,evidence: evidence,bundle: artifact,binding: binding)
    }
    @Test func conditionProjectionUsesTheIndividualCheckedObligationAndRedactsFiniteInputs() throws {
        func claim(_ name: String, _ domain: String, _ proposition: String) -> VerificationClaim {
            VerificationClaim(id: id(name), obligation: name, proposition: proposition, assumptions: [],
                domain: domain, scope: "Model only", execution: "completed", outcome: "unproved",
                translation: "UNVALIDATED", toolIdentities: [:], artifactDigests: [])
        }
        let quantified = #"{"name":"bounds","entry":"includes","requires":"arg0","ensures":"result == arg1"}"#
        let result = try #require(try VerifiedCondition.record(claim("bounds","generatedModel.lean.quantified",quantified), bundleID: id("bundle")))
        #expect(result["ensures"] == .string("result == arg1"))
        #expect(result["outcome"] == .string("unproved"))
        #expect(result["entry"] == .string("includes"))
        #expect(throws: InvarError.self) {
            try VerifiedCondition.record(claim("other","generatedModel.lean.quantified",quantified), bundleID: id("bundle"))
        }
        let finite = #"{"name":"edge","entry":"f","arguments":["private-input"],"expected":{"status":"returned","value":"private-output"}}"#
        let scenario = try #require(try VerifiedCondition.record(claim("edge","generatedModel.tla.finite",finite), bundleID: id("finite")))
        #expect(scenario["expectedStatus"] == .string("returned"))
        #expect(!String(decoding: try CanonicalJSON.encode(scenario), as: UTF8.self).contains("private-"))
    }
    private func descriptor(extraction: String = "available") -> FormalGraphDescriptor {
        FormalGraphDescriptor(id: id("graph"),kind: .tlaStateSpace,roots: [id("a")],artifactDigests: [],producer: "fixture/1",scope: "Bounded fixture",complete: false,extraction: extraction,diagnostics: [])
    }
    private func query(cursor: String? = nil,direction: String = "outgoing") -> FormalGraphQuery {
        FormalGraphQuery(graphID: id("graph"),roots: [id("a")],relations: [],direction: direction,depth: 0,cursor: cursor)
    }
    private func page(cursor: String? = nil,label: String = "private secret 日本語") -> FormalGraphPage {
        let nodes = [FormalNode(id: id("a"),kind: "state",label: label,attributes: ["initial":"true","secret":"never-publish"],ranges: [],claimIDs: [],stateValue: .integer("123456789012345678901234567890")),FormalNode(id: id("b"),kind: "state",label: "other secret",attributes: ["index":"1"],ranges: [],claimIDs: [],stateValue: .string("private state 日本語"))]
        let edges = [FormalEdge(id: id("edge"),source: id("a"),target: id("b"),kind: "transition",attributes: ["secret":"private edge"])]
        return FormalGraphPage(graphID: id("graph"),nodes: nodes,edges: edges,frontier: [id("b")],selectionComplete: false,nextCursor: cursor)
    }
    @Test func projectionPreservesRootsEdgesAndIndependentAxesWithoutPublishingPrivateValues() throws {
        let context = try context(), result = try FormalGraphProjector().project(page(cursor: "opaque-private-cursor"),descriptor: descriptor(),query: query(),context: context)
        let data = result.contribution.data
        let bytes = try CanonicalJSON.encode(data), text = String(decoding: bytes,as: UTF8.self)
        for secret in ["123456789012345678901234567890","private secret","never-publish","private state","private edge","opaque-private-cursor"] { #expect(!text.contains(secret)) }
        let nodes = data["nodes"].array, edges = data["edges"].array
        #expect(nodes.count == 2 && edges.count == 1)
        #expect(nodes[0]["id"].string?.hasPrefix("invar:") == true)
        #expect(nodes[0]["attributes"]["isDeclaredRoot"] == .bool(true))
        #expect(edges[0]["source"] == nodes[0]["id"] && edges[0]["target"] == nodes[1]["id"])
        #expect(edges[0]["kind"] == .string("transition"))
        #expect(data["metadata"]["outcome"] == .string("violated"))
        #expect(data["metadata"]["translation"] == .string("unvalidated"))
        #expect(data["metadata"]["applicability"] == .string("stale"))
        #expect(data["metadata"]["upstreamDependencyStatus"] == .string("unknown"))
        #expect(data["metadata"]["producerScopeComplete"] == .bool(false))
        #expect(data["metadata"]["selectionComplete"] == .bool(false))
        #expect(data["metadata"]["hasMorePages"] == .bool(true))
        #expect(data["metadata"]["viewDigest"] == .string(context.view.sha256))
    }
    @Test func originalCursorNamespaceDoesNotChangeProjectionButOriginalContentDoes() throws {
        let context = try context(), projector = FormalGraphProjector()
        let first = try projector.project(page(cursor: "reader-one"),descriptor: descriptor(),query: query(),context: context)
        let second = try projector.project(page(cursor: "reader-two"),descriptor: descriptor(),query: query(cursor: "another-private-reader-cursor"),context: context)
        #expect(first.id == second.id)
        #expect(first.contribution == second.contribution)
        let changed = try projector.project(page(cursor: "reader-one",label: "different original content"),descriptor: descriptor(),query: query(),context: context)
        #expect(changed.id != first.id)
        let terminal = try projector.project(page(),descriptor: descriptor(),query: query(),context: context)
        #expect(terminal.id != first.id)
        let anotherScope = try projector.project(page(cursor: "reader-one"),descriptor: descriptor(),query: query(direction: "incoming"),context: context)
        #expect(anotherScope.id != first.id)
        let anotherBinding = try self.context(manifestDigest: id("different-owner-binding"))
        let rebound = try projector.project(page(cursor: "reader-one"),descriptor: descriptor(),query: query(),context: anotherBinding)
        #expect(rebound.id != first.id)
    }
    @Test func unavailableExtractionAndDanglingEndpointsAreExplicitFailures() throws {
        let context = try context(), projector = FormalGraphProjector()
        #expect(throws: InvarError.self) { try projector.project(page(),descriptor: descriptor(extraction: "unavailable"),query: query(),context: context) }
        let original = page()
        let dangling = FormalGraphPage(graphID: original.graphID,nodes: original.nodes,edges: [FormalEdge(id: id("edge"),source: id("a"),target: id("absent"),kind: "transition",attributes: [:])],frontier: [],selectionComplete: true)
        #expect(throws: InvarError.self) { try projector.project(dangling,descriptor: descriptor(),query: query(),context: context) }
    }
}
