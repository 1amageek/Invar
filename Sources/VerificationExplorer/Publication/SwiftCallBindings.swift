import ArchitectureCore
import ArchitectureFrontend
import Foundation
import VerificationCore

/// Links a checked free-function entry to source syntax. Call sites are candidates, not dispatch evidence.
enum SwiftCallBindings {
    static func resolve(entry: String, source: String, digest: String, capture: CapturedWorkspace) throws -> JSONValue {
        let inventory = capture.inventory
        func input(_ path: String, _ data: Data) -> SourceInput {
            SourceInput(workspaceID: inventory.workspaceID, path: path, language: "swift", bytes: data,
                        contextDigest: inventory.contextDigest, generation: 0)
        }
        func unavailable(_ reason: String) -> JSONValue { .object(["status": .string(reason)]) }
        guard let bytes = capture.files[source], Canonical.digest(bytes) == digest else {
            throw InvarError("INPUT_MISMATCH", "Compiled source differs from the verification capture")
        }
        let declaration = input(source, bytes)
        let ast: SyntaxNode
        do { ast = try SyntaxParser().parse(declaration) }
        catch let error as ArchitectureError { return unavailable(error.code) }
        let functions = ast.children.filter { node in
            node.kind == "function_declaration" && node.child("name").map(declaration.text) == entry
        }
        guard functions.count == 1, let function = functions.first else { return unavailable("entryUnavailableOrAmbiguous") }
        let params = function.children.filter { $0.kind == "parameter" }
        let names = params.compactMap { parameter in
            parameter.children.first { $0.field == "name" && $0.kind == "simple_identifier" }.map(declaration.text)
        }
        guard names.count == params.count, !names.contains("_") else { return unavailable("parameterNamesUnavailable") }
        let labels = zip(params, names).map { parameter, name in parameter.child("external_name").map(declaration.text) ?? name }
        let files = inventory.entities.filter { $0.kind == "file" && $0.path?.hasSuffix(".swift") == true }
        var sites: [JSONValue] = [], partial = false, parsedBytes = 0
        let ambiguous = inventory.entities.contains { $0.language == "swift" && $0.name == entry && $0.kind == "function" && $0.path != source }
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        let needle = Data(entry.utf8)
        for file in files.sorted(by: { ($0.path ?? "") < ($1.path ?? "") }) where !ambiguous {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline, sites.count < 16 else { partial = true; break }
            guard let path = file.path, let data = capture.files[path], data.range(of: needle) != nil else { continue }
            parsedBytes += data.count
            guard parsedBytes <= 8 * 1024 * 1024 else { partial = true; break }
            let caller = input(path, data)
            guard caller.digest == file.sourceDigest else { partial = true; continue }
            let tree: SyntaxNode
            do { tree = path == source ? ast : try SyntaxParser().parse(caller) }
            catch is ArchitectureError { partial = true; continue }
            var stack: [(SyntaxNode, Bool)] = [(tree, false)]
            while let (node, isIf) = stack.popLast() {
                if node.kind == "call_expression", node.children.count == 2,
                   let callee = node.children.first, callee.kind == "simple_identifier", caller.text(callee) == entry,
                   let suffix = node.children.last, suffix.kind == "call_suffix", suffix.namedChildren.count == 1,
                   let list = suffix.namedChildren.first, list.kind == "value_arguments" {
                    let args = list.namedChildren.filter { $0.kind == "value_argument" }
                    let values = args.compactMap { $0.child("value") }
                    if args.count == labels.count, values.count == args.count,
                       args.map({ $0.child("name").map(caller.text) ?? "_" }) == labels {
                        guard sites.count < 16, node.end - node.start <= 16384 else { partial = true; continue }
                        let ranges = values.map { JSONValue.object(["start": .number(Double($0.start)), "end": .number(Double($0.end))]) }
                        sites.append(.object(["entityID": .string(file.id), "path": .string(path), "digest": .string(caller.digest),
                            "line": .number(Double(data.prefix(node.start).count(where: { $0 == 10 }) + 1)),
                            "start": .number(Double(node.start)), "end": .number(Double(node.end)),
                            "ifCondition": .bool(isIf), "arguments": .array(ranges)]))
                    }
                }
                for child in node.children.reversed() {
                    stack.append((child, node.kind == "if_statement" && child.field == "condition"))
                }
            }
        }
        return .object(["parameters": .array(names.map(JSONValue.string)), "sites": .array(sites),
                        "status": .string(ambiguous ? "ambiguousCallTarget" : partial ? "partial" : "syntaxCandidates")])
    }
}
