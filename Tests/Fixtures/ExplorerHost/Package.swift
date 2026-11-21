// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "InvarExplorerHost",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: "../../.."),.package(path: "../../../../ArchitectureExplorer"),.package(path: "../../../../Formal")],
    targets: [.executableTarget(name: "InvarExplorerHost",dependencies: [
        .product(name: "VerificationFormal",package: "invar"),.product(name: "FormalEvidence",package: "formal"),
        .product(name: "VerificationCore",package: "invar"),.product(name: "VerificationClient",package: "invar"),
        .product(name: "ArchitectureExtensions",package: "architectureexplorer"),.product(name: "ArchitectureClient",package: "architectureexplorer"),.product(name: "ArchitectureCore",package: "architectureexplorer"),
        .product(name: "ArchitectureService",package: "architectureexplorer"),.product(name: "ArchitectureStore",package: "architectureexplorer")
    ],exclude: ["DESIGN.md"]),.executableTarget(name: "InvarConnectionFailure",dependencies: [
        .product(name: "VerificationExplorer",package: "invar"),.product(name: "VerificationCore",package: "invar"),
        .product(name: "ArchitectureCore",package: "architectureexplorer"),.product(name: "ArchitectureExtensions",package: "architectureexplorer")
    ],exclude: ["DESIGN.md"])],swiftLanguageModes: [.v6]
)
