// swift-tools-version: 6.4
import PackageDescription

let modules = ["VerificationCore", "VerificationDiscovery", "VerificationPlanner", "VerificationStore", "VerificationExplorer", "VerificationBackends", "VerificationRuntime", "VerificationClient", "VerificationDaemon", "VerificationFormal"]
func excludes(_ components: [String]) -> [String] { ["DESIGN.md"] + components.map { $0 + "/DESIGN.md" } }
let package = Package(
    name: "Invar", platforms: [.macOS("27.0")],
    products: modules.map { .library(name: $0, targets: [$0]) } + [.executable(name: "inver", targets: ["inver"])],
    dependencies: [
        .package(url: "https://github.com/1amageek/ArchitectureExplorer.git", revision: "4390dcd21400cb3af37d891a8644c6acde7eef66"),
        .package(url: "https://github.com/1amageek/swift-formal.git", revision: "204f5e71903b7815da9c70fc44ab416ddb0f68c5"),
        .package(url: "https://github.com/1amageek/swift-sdk.git", revision: "6cdd633b7f782bffba6c2859b28147b2ffa1fc57"),
    ],
    targets: [
        .target(name: "InvarMap", dependencies: [.product(name: "ArchitectureFrontend", package: "architectureexplorer"), .product(name: "ArchitectureCore", package: "architectureexplorer")], exclude: ["DESIGN.md"]),
        .target(name: "VerificationCore", exclude: excludes(["Domain", "Assessment", "Changes", "Evidence"])),
        .target(name: "VerificationDiscovery", dependencies: ["VerificationCore"], exclude: excludes(["Rules", "Changes"])),
        .target(name: "VerificationPlanner", dependencies: ["VerificationCore"], exclude: excludes(["Planning"])),
        .systemLibrary(name: "CInvarSQLite"),
        .target(name: "VerificationStore", dependencies: ["VerificationCore", "CInvarSQLite"], exclude: excludes(["Persistence"])),
        .target(name: "VerificationExplorer", dependencies: ["VerificationCore", .product(name: "ArchitectureFrontend", package: "architectureexplorer"), .product(name: "FormalEvidence", package: "swift-formal"), .product(name: "ArchitectureClient", package: "architectureexplorer"), .product(name: "ArchitectureIR", package: "architectureexplorer"), .product(name: "ArchitectureExtensions", package: "architectureexplorer"), .product(name: "ArchitectureCore", package: "architectureexplorer")], exclude: excludes(["Connection", "Publication"])),
        .target(name: "VerificationBackends", dependencies: ["VerificationCore", .product(name: "ArchitectureFrontend", package: "architectureexplorer"), .product(name: "ArchitectureCore", package: "architectureexplorer"), .product(name: "FormalCore", package: "swift-formal"), .product(name: "FormalIR", package: "swift-formal"), .product(name: "FormalCompiler", package: "swift-formal"), .product(name: "FormalValidation", package: "swift-formal"), .product(name: "FormalEvidence", package: "swift-formal")], exclude: excludes(["Static", "Formal", "Native", "Artifacts", "Project"])),
        .target(name: "VerificationRuntime", dependencies: ["VerificationCore"], exclude: excludes(["Scheduling", "Execution", "Coordination", "Watching"])),
        .target(name: "VerificationFormal", dependencies: ["VerificationCore", .product(name: "FormalEvidence", package: "swift-formal")], exclude: excludes(["Queries"])),
        .target(name: "VerificationClient", dependencies: ["VerificationCore", "VerificationFormal", .product(name: "ArchitectureClient", package: "architectureexplorer"), .product(name: "FormalEvidence", package: "swift-formal"), .product(name: "ArchitectureCore", package: "architectureexplorer")], exclude: excludes(["Session", "Formal"])),
        .target(name: "VerificationDaemon", dependencies: ["VerificationCore", "VerificationStore", "VerificationRuntime", "VerificationExplorer", "VerificationBackends", "VerificationDiscovery", "VerificationPlanner", "VerificationFormal", .product(name: "ArchitectureClient", package: "architectureexplorer"), .product(name: "FormalEvidence", package: "swift-formal"), .product(name: "ArchitectureExtensions", package: "architectureexplorer"), .product(name: "FormalValidation", package: "swift-formal"), .product(name: "ArchitectureCore", package: "architectureexplorer")], exclude: excludes(["Hosting", "Workers", "WorkspaceOperations", "FormalQueries", "ProviderActions"])),
        .executableTarget(name: "inver", dependencies: modules.map { Target.Dependency.target(name: $0) } + ["InvarMap", .product(name: "MCP", package: "swift-sdk"), .product(name: "ArchitectureExtensions", package: "architectureexplorer"), .product(name: "FormalCore", package: "swift-formal"), .product(name: "FormalValidation", package: "swift-formal"), .product(name: "ArchitectureClient", package: "architectureexplorer"), .product(name: "ArchitectureCore", package: "architectureexplorer")], path: "Sources/invar", exclude: excludes(["Commands", "MCP"])),
        .testTarget(name: "InvarTests", dependencies: modules.map { Target.Dependency.target(name: $0) } + ["InvarMap", .product(name: "FormalValidation", package: "swift-formal"), .product(name: "FormalEvidence", package: "swift-formal")]),
    ], swiftLanguageModes: [.v6]
)
