// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "InvarExplorerHost",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../../.."),
        .package(url: "https://github.com/1amageek/ArchitectureExplorer.git", revision: "4390dcd21400cb3af37d891a8644c6acde7eef66"),
        .package(url: "https://github.com/1amageek/swift-formal.git", revision: "204f5e71903b7815da9c70fc44ab416ddb0f68c5"),
    ],
    targets: [.executableTarget(name: "InvarExplorerHost",dependencies: [
        .product(name: "VerificationFormal",package: "invar"),.product(name: "FormalEvidence",package: "swift-formal"),
        .product(name: "VerificationCore",package: "invar"),.product(name: "VerificationClient",package: "invar"),
        .product(name: "ArchitectureExtensions",package: "architectureexplorer"),.product(name: "ArchitectureClient",package: "architectureexplorer"),.product(name: "ArchitectureCore",package: "architectureexplorer"),
        .product(name: "ArchitectureService",package: "architectureexplorer"),.product(name: "ArchitectureStore",package: "architectureexplorer")
    ],exclude: ["DESIGN.md"]),.executableTarget(name: "InvarConnectionFailure",dependencies: [
        .product(name: "VerificationExplorer",package: "invar"),.product(name: "VerificationCore",package: "invar"),
        .product(name: "ArchitectureCore",package: "architectureexplorer"),.product(name: "ArchitectureExtensions",package: "architectureexplorer")
    ],exclude: ["DESIGN.md"])],swiftLanguageModes: [.v6]
)
