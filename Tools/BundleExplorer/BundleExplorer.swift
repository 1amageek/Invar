import Foundation
import PackagePlugin

@main
struct BundleExplorer: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let host = try context.tool(named: "architecture-host").url
        let products = host.deletingLastPathComponent()
        let toolSuffix = host.lastPathComponent.hasSuffix("-tool") ? "-tool" : ""
        let bundles = ["ArchitectureGraph", "ArchitectureWeb", "ArchitectureHTTPHost"].map {
            products.appending(path: "ArchitectureExplorer_\($0)\(toolSuffix).bundle")
        }
        let files = [(host, "architecture-host")] + bundles.map { ($0, $0.lastPathComponent) }
        return files.map { source, name in
            let output = context.pluginWorkDirectoryURL.appending(path: name)
            return .buildCommand(
                displayName: "Bundle Explorer: \(name)",
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: [source.path, output.path],
                inputFiles: [source],
                outputFiles: [output]
            )
        }
    }
}
