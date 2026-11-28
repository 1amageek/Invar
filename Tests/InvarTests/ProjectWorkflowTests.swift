import Foundation
import FormalValidation
import Testing
import VerificationCore

@Suite(.timeLimit(.minutes(1))) struct ProjectWorkflowTests {
    @Test func nativeAssessmentChecksActualBuilderReportsAndRejectsPromotedLabels() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("project-gates-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work,withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: work) } catch { Issue.record(error) } }
        let process = try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/python3"),arguments: [root.appendingPathComponent("Tools/project-report.test.py").path,"--write-fixtures",work.path],directory: work,environment: ["PYTHONDONTWRITEBYTECODE":"1","PATH":"/usr/bin:/bin"],log: work.appendingPathComponent("builder"),timeout: 15,maximumOutputBytes: 1048576,maximumWorkspaceBytes: 8388608)
        #expect(process.exitCode == 0)
        for (name,expected) in [("passed","passed"),("incomplete","incomplete"),("revision","incomplete")] {
            let bytes = try Data(contentsOf: work.appendingPathComponent(name + ".json"))
            #expect(try ProjectReportAssessment.outcome(bytes) == expected)
        }
        let bytes = try Data(contentsOf: work.appendingPathComponent("passed.json"))
        let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String:Any])
        for mutation in ["workflow","claims","review","return","generation","correspondence","missingArchitecture","unboundArchitecture","missingIntent"] {
            var document = original, metadata = try #require(document["metadata"] as? [String:Any])
            var report = try #require(metadata["verificationReport"] as? [String:Any])
            switch mutation {
            case "workflow": report.removeValue(forKey: "workflow")
            case "missingArchitecture": report["architectureInputs"] = [[String:Any]]()
            case "unboundArchitecture", "missingIntent":
                var workflow = try #require(report["workflow"] as? [String:Any])
                var reviews = try #require(workflow["reviews"] as? [[String:Any]])
                let inputs = try #require(reviews[0]["inputs"] as? [[String:Any]])
                if mutation == "missingIntent" { reviews[0].removeValue(forKey: "intent") }
                else { reviews[0]["inputs"] = inputs.filter { $0["path"] as? String != "ARCHITECTURE.dsl" } }
                workflow["reviews"] = reviews; report["workflow"] = workflow
            case "claims":
                var rows = try #require(report["requirements"] as? [[String:Any]])
                var assessment = try #require(rows[0]["implementation"] as? [String:Any]); assessment["claims"] = [String](); rows[0]["implementation"] = assessment; report["requirements"] = rows
            case "review", "return":
                var workflow = try #require(report["workflow"] as? [String:Any])
                if mutation == "return" { workflow["returnTo"] = "integration" }
                else {
                    var reviews = try #require(workflow["reviews"] as? [[String:Any]]); reviews[0]["bindingComplete"] = false; workflow["reviews"] = reviews
                }
                report["workflow"] = workflow
            default:
                var claims = try #require(report["evidence"] as? [[String:Any]])
                let index = try #require(claims.firstIndex(where: { ($0["activity"] as? String) == (mutation == "generation" ? "implementationCheck" : "correspondenceCheck") }))
                if mutation == "generation" { claims[index]["activity"] = "modelGeneration"; claims[index]["method"] = "generation" }
                else { claims[index]["modelInputs"] = [["path":"other-model.json","sha256":String(repeating: "f",count: 64)]] }
                report["evidence"] = claims
            }
            metadata["verificationReport"] = report; document["metadata"] = metadata
            let changed = try JSONSerialization.data(withJSONObject: document)
            #expect(throws: (any Error).self) { try ProjectReportAssessment.outcome(changed) }
        }
    }
}
