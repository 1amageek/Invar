import ArchitectureCore
import ArchitectureFrontend
import FormalCompiler
import Foundation
import VerificationCore

enum SwiftExpressionSelection {
    private enum Binding { case integer, array, unknown }

    static func extract(_ bytes: Data, path: String, selection: Range<Int>) throws -> [SwiftExpressionSite] {
        let input = SourceInput(workspaceID: "", path: path, language: "swift", bytes: bytes, contextDigest: "", generation: 0)
        let tree: SyntaxNode
        do { tree = try SyntaxParser().parse(input) }
        catch let error as ArchitectureError { throw InvarError(error.code, error.message, exitCode: error.exitCode) }
        var sites: [SwiftExpressionSite] = []
        var scopes: [[String: Binding]] = []
        func binding(_ name: SyntaxNode) -> Binding? {
            let key = input.text(name)
            for scope in scopes.reversed() { if let found = scope[key] { return found } }
            return nil
        }
        func declarations(_ parent: SyntaxNode) -> [String: Binding] {
            var names: [String: Binding] = [:]
            for child in parent.namedChildren {
                let name: SyntaxNode?, type: SyntaxNode?
                switch child.kind {
                case "parameter","lambda_parameter":
                    name = child.children.first { $0.field == "name" && $0.kind == "simple_identifier" }
                    type = child.children.last { $0.field == "name" && $0.kind != "simple_identifier" }
                case "property_declaration":
                    name = child.child("name")?.child("bound_identifier")
                    type = child.children.first { $0.kind == "type_annotation" }?.child("name")
                default: continue
                }
                guard let name else { continue }
                let key = input.text(name)
                if names[key] != nil { names[key] = .unknown }
                else if type?.kind == "array_type" { names[key] = .array }
                else if let type, ["Int","Int64","Swift.Int","Swift.Int64"].contains(input.text(type)) { names[key] = .integer }
                else { names[key] = .unknown }
            }
            return names
        }
        func operand(_ node: SyntaxNode) -> SwiftExpressionSite.Operand? {
            switch node.kind {
            case "integer_literal", "prefix_expression":
                guard node.end - node.start <= 24, let value = Int64(input.text(node)) else { return nil }
                return .integer(value)
            case "navigation_expression":
                guard let target = node.child("target"), target.kind == "simple_identifier", binding(target) == .array, let suffix = node.child("suffix"),
                      suffix.end - suffix.start == 6, input.text(suffix) == ".count" else { return nil }
                return .count
            case "simple_identifier": return binding(node) == .integer ? .scalar : nil
            default: return nil
            }
        }
        func visit(_ node: SyntaxNode, isCallTarget: Bool) throws {
            guard selection.overlaps(node.start..<node.end), node.kind != "macro_invocation" else { return }
            try Task.checkCancellation()
            var locals = declarations(node)
            if node.kind == "lambda_literal", let signature = node.children.first(where: { $0.kind == "lambda_function_type" }) {
                for parameter in signature.descendants(["lambda_parameter"]) {
                    if let name = parameter.child("name") { locals[input.text(name)] = .unknown }
                }
            }
            let pushed = !locals.isEmpty
            if pushed { scopes.append(locals) }
            defer { if pushed { scopes.removeLast() } }
            if selection.lowerBound <= node.start && node.end <= selection.upperBound {
                if !isCallTarget, ["additive_expression","multiplicative_expression"].contains(node.kind),
                   let left = node.child("lhs"), let right = node.child("rhs"), let operation = node.child("op"),
                   let op = SwiftExpressionSite.Operation(rawValue: input.text(operation)),
                   let lhs = operand(left), let rhs = operand(right) {
                    sites.append(.init(bytes: node.start..<node.end, expression: .arithmetic(lhs, op, rhs)))
                } else if ["if_statement","if_expression","guard_statement"].contains(node.kind),
                          let first = node.children.first(where: { $0.field == "condition" }),
                          let last = node.children.last(where: { $0.field == "condition" }) {
                    var predicate = SwiftExpressionSite.Predicate.opaque
                    if first.start == last.start, let left = first.child("lhs"), let right = first.child("rhs"),
                       let operation = first.child("op"), let comparison = SwiftExpressionSite.Comparison(rawValue: input.text(operation)),
                       let lhs = operand(left), let rhs = operand(right) {
                        predicate = .comparison(lhs, comparison, rhs)
                    }
                    sites.append(.init(bytes: first.start..<last.end, expression: .conditional(isGuard: node.kind == "guard_statement", predicate: predicate)))
                }
            }
            for (index, child) in node.children.enumerated() where child.named {
                try visit(child, isCallTarget: node.kind == "call_expression" && index == 0 || node.kind == "navigation_expression" && child.field == "target")
            }
        }
        try visit(tree, isCallTarget: false)
        guard !sites.isEmpty else { throw InvarError("UNSUPPORTED_SOURCE_PROFILE","No supported integer arithmetic or conditional branches in the selected Swift source.",exitCode: 3) }
        return sites
    }
}
