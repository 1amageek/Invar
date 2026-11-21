import Foundation
import InvarMap
import Testing

struct MapGenerationTests {
    @Test(.timeLimit(.minutes(1))) func packageDeclarationsKeepIndependentOwnershipAcrossRegeneration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }

        let packages = ["Services/Booking", "Jobs/Worker"]
        for package in packages {
            let directory = root.appendingPathComponent(package)
            let sources = directory.appendingPathComponent("Sources/Runner")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try Data(#"let package = Package(name: "Demo", targets: [.executableTarget(name: "Runner")])"#.utf8)
                .write(to: directory.appendingPathComponent("Package.swift"))
            try Data("@main struct Runner { static func main() {} }".utf8)
                .write(to: sources.appendingPathComponent("Entry.swift"))
        }
        let arguments = ["--workspace", root.path, "--system", "Demo", "--package", packages[0], "--package", packages[1]]
        try MapCommand.run(arguments)
        let oldOutput = root.appendingPathComponent("workspace.dsl")
        #expect(throws: (any Error).self) { try MapCommand.run(arguments + ["--out", oldOutput.path]) }
        #expect(!FileManager.default.fileExists(atPath: oldOutput.path))
        let workspace = root.appendingPathComponent("ARCHITECTURE.dsl")
        let originalWorkspace = try String(contentsOf: workspace, encoding: .utf8)
        for package in packages {
            let path = package + "/containers.dsl"
            #expect(originalWorkspace.contains("!include \"\(path)\""))
            let declaration = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            #expect(declaration.contains(package + "/Sources/Runner/Entry.swift"))
            #expect(declaration.components(separatedBy: "= container ").count == 2)
        }
        let protected = root.appendingPathComponent(packages[0] + "/containers.dsl")
        let untouched = root.appendingPathComponent(packages[1] + "/containers.dsl")
        let originalOther = try Data(contentsOf: untouched)
        try Data("// Authored locally".utf8).write(to: protected)
        #expect(throws: (any Error).self) { try MapCommand.run(arguments) }
        #expect(try String(contentsOf: protected, encoding: .utf8) == "// Authored locally")
        #expect(try Data(contentsOf: untouched) == originalOther)
        #expect(try String(contentsOf: workspace, encoding: .utf8) == originalWorkspace)
    }
    @Test(.timeLimit(.minutes(1))) func onlyBoundRequestsBecomeExternalSystems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("Sources/Runner")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        try Data(#"let package = Package(name: "Demo", targets: [.executableTarget(name: "Runner")])"#.utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        let file = target.appendingPathComponent("Entry.swift")
        let source = """
        import Foundation
        @main struct Runner {
            static func main() async throws {
                let unused = "https://ignored.invalid/"
                let request = URLRequest(url: URL(string: "https://endpoint.invalid/send")!)
                let response = try await URLSession.shared.data(for: request)
            }
        }
        """
        try Data(source.utf8).write(to: file)
        func model() throws -> String { try RuntimeDiscovery.generate(root: root, system: "Demo", packages: ["."]).values.sorted().joined(separator: "\n") }
        let dsl = try model()
        #expect(dsl.contains("softwareSystem \"endpoint.invalid\""))
        #expect(dsl.contains("group \"Remote service · endpoint.invalid\" {"))
        #expect(dsl.contains("group \"Local runtimes\" {\n            subject = softwareSystem"))
        let start = try #require(source.utf8.firstIndex(of: 64))
        let offset = source.utf8.distance(from: source.utf8.startIndex, to: start)
        #expect(dsl.contains("// Entry: type \(offset)..<\(source.utf8.count) sha256="))
        #expect(!dsl.contains("ignored.invalid"))
        #expect(try model() == dsl)
        try Data(source.replacingOccurrences(of: "data(for: request)", with: "data(for: different)").utf8).write(to: file)
        #expect(try !model().contains("endpoint.invalid"))
        let args = ["--workspace", root.path, "--system", "Demo", "--package", "."]
        try MapCommand.run(args)
        let rootDSL = try String(contentsOf: root.appendingPathComponent("ARCHITECTURE.dsl"), encoding: .utf8)
        #expect(rootDSL.contains("!include \"containers.dsl\""))
        #expect(!rootDSL.contains("= container "))
        let declarations = root.appendingPathComponent("containers.dsl")
        #expect(try String(contentsOf: declarations, encoding: .utf8).contains("= container \"Runner\""))
        let output = root.appendingPathComponent("ARCHITECTURE.dsl")
        try Data("workspace {}".utf8).write(to: output)
        #expect(throws: (any Error).self) {
            try MapCommand.run(["--workspace", root.path, "--system", "Demo", "--package", ".", "--out", output.path])
        }
        #expect(try String(contentsOf: output, encoding: .utf8) == "workspace {}")
    }
    @Test(.timeLimit(.minutes(1))) func onlyTheHostedEntryExposesAnInboundHTTPInterface() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("Sources/Runner")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        try Data(#"let package = Package(name: "Demo", targets: [.target(name: "Site"), .executableTarget(name: "Runner", dependencies: ["Site"])])"#.utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        let site = root.appendingPathComponent("Sources/Site")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        let app = site.appendingPathComponent("Site.swift")
        try Data("import SwiftWeb\nstruct Site: SwiftWeb.App {}".utf8).write(to: app)
        let file = target.appendingPathComponent("Entry.swift")
        let source = """
        import Site
        import SwiftWebHTTPServerHost
        @main struct Runner {
            static func main() async throws { try await Site.run() }
        }
        """
        func generate(_ code: String) throws -> String {
            try Data(code.utf8).write(to: file)
            return try RuntimeDiscovery.generate(root: root, system: "Demo", packages: ["."]).values.sorted().joined(separator: "\n")
        }
        let model = try generate(source)
        #expect(model.contains("http_client -> subject") && model.contains("http_client -> app_"))
        #expect(model.contains("Sources/Runner/Entry.swift:4"))
        let unrelated = source.replacingOccurrences(of: "static func main()", with: "static func main() {}\n    static func unused()")
        #expect(try !generate(unrelated).contains("http_client"))
        #expect(try !generate(source.replacingOccurrences(of: "import SwiftWebHTTPServerHost", with: "")).contains("http_client"))
        try Data("struct Site { static func run() {} }".utf8).write(to: app)
        #expect(try !generate(source).contains("http_client"))
    }
}
