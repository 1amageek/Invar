import Foundation
import VerificationCore

/// Retains the independently validated receipt closure after attempt cleanup.
enum ProjectEvidenceArchive {
    static func encode(root: URL,manifest: String,check: ProjectCheck,maximumBytes: Int) throws -> Data {
        var paths = Set(check.contracts + [manifest,check.report])
        let manifestBytes = try FixedInputReader.read(root.appendingPathComponent(manifest),maximum: maximumBytes)
        guard let value = try JSONSerialization.jsonObject(with: manifestBytes) as? [String:Any],
            let inventory = value["inventory"] as? [String:Any], let source = inventory["source"] as? [String:Any],
            let sourcePath = source["path"] as? String, let receipts = value["receipts"] as? [[String:Any]] else { throw InvarError("INVALID_RESULT","Validated project manifest lost its receipt closure") }
        paths.insert(sourcePath)
        if let acceptance = value["userAcceptance"] as? [String:Any], let path = acceptance["path"] as? String {
            paths.insert(path)
        }
        let governing = value["governingDocuments"] as? [[String:Any]] ?? []
        let architecture = value["architectureInputs"] as? [[String:Any]] ?? []
        for reference in governing + architecture {
            guard let path = reference["path"] as? String else { throw InvarError("INVALID_RESULT","Invalid governing document") }; paths.insert(path)
        }
        for reference in (value["productionInputs"] as? [[String:Any]] ?? []) {
            guard let path = reference["path"] as? String else { throw InvarError("INVALID_RESULT","Invalid production source") }; paths.insert(path)
        }
        for reference in (value["reviews"] as? [[String:Any]] ?? []) {
            guard let path = reference["path"] as? String else { throw InvarError("INVALID_RESULT","Invalid stage review") }
            _ = try Canonical.relative(path); paths.insert(path)
            let bytes = try FixedInputReader.read(root.appendingPathComponent(path),maximum: maximumBytes)
            guard let review = try JSONSerialization.jsonObject(with: bytes) as? [String:Any], let inputs = review["inputs"] as? [[String:Any]] else { throw InvarError("INVALID_RESULT","Invalid stage review closure") }
            for input in inputs { guard let inputPath = input["path"] as? String else { throw InvarError("INVALID_RESULT","Missing review input") }; paths.insert(inputPath) }
        }
        for reference in receipts {
            guard let path = reference["path"] as? String else { throw InvarError("INVALID_RESULT","Invalid receipt path") }
            _ = try Canonical.relative(path); paths.insert(path)
            let bytes = try FixedInputReader.read(root.appendingPathComponent(path),maximum: maximumBytes)
            guard let receipt = try JSONSerialization.jsonObject(with: bytes) as? [String:Any], let inputs = receipt["inputs"] as? [[String:Any]], let outputs = receipt["outputs"] as? [[String:Any]] else { throw InvarError("INVALID_RESULT","Invalid receipt closure") }
            for file in inputs + outputs {
                guard let filePath = file["path"] as? String else { throw InvarError("INVALID_RESULT","Missing receipt file") }; paths.insert(filePath)
            }
        }
        guard paths.count <= 4096 else { throw InvarError("RESOURCE_LIMIT","Project evidence archive exceeds its file limit",exitCode: 6) }
        var total = 0, files: [[String:String]] = []
        for path in paths.sorted() {
            try Task.checkCancellation(); _ = try Canonical.relative(path)
            let bytes = try FixedInputReader.read(root.appendingPathComponent(path),maximum: max(0,maximumBytes-total))
            total += bytes.count
            guard total <= maximumBytes else { throw InvarError("RESOURCE_LIMIT","Project receipt closure exceeds artifact budget",exitCode: 6) }
            files.append(["path":path,"sha256":Canonical.digest(bytes),"base64":bytes.base64EncodedString()])
        }
        return try JSONSerialization.data(withJSONObject: ["schemaVersion":1,"manifest":manifest,"files":files],options: [.sortedKeys])
    }
}
