import Darwin
import Foundation
import VerificationCore

struct SetupCommand {
    enum Profile: String, CaseIterable {
        case formal, deslop, stitch
        case formalCLI = "formal-cli"
    }

    struct Readiness: Encodable {
        let profile: String
        var paths: [String: String] = [:]
        var image: String?
        var diagnostic: String?
        var ready: Bool { diagnostic == nil }

        private enum CodingKeys: String, CodingKey { case profile, paths, image, diagnostic, ready }

        func encode(to encoder: Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(profile, forKey: .profile)
            try fields.encode(paths, forKey: .paths)
            try fields.encodeIfPresent(image, forKey: .image)
            try fields.encodeIfPresent(diagnostic, forKey: .diagnostic)
            try fields.encode(ready, forKey: .ready)
        }
    }

    static let help = "invar setup [--workspace PATH] [--tools formal,deslop,stitch,formal-cli] [--stitch-language LANGUAGE] [--tool-root PATH]"

    static func run(_ arguments: [String]) async throws -> (Data, Int32) {
        let keys: Set = ["--workspace", "--tools", "--stitch-language", "--tool-root"]
        var options: [String: String] = [:]
        var items = arguments.makeIterator()
        while let key = items.next() {
            guard keys.contains(key), options[key] == nil, let value = items.next(), !value.hasPrefix("--") else {
                throw InvarError("INVALID_ARGUMENT", help, exitCode: 2)
            }
            options[key] = value
        }
        let tools = try options["--tools"].map { input in
            try input.split(separator: ",", omittingEmptySubsequences: false).map { name in
                guard let profile = Profile(rawValue: String(name)) else {
                    throw InvarError("INVALID_ARGUMENT", "Unknown setup tool \(name)", exitCode: 2)
                }
                return profile
            }
        } ?? Profile.allCases
        let languages: Set = ["cpp", "python", "javascript", "java", "go", "rust", "ruby", "swift", "objc"]
        let language = options["--stitch-language"]
        if let language, !tools.contains(.stitch) || !languages.contains(language) {
            throw InvarError("INVALID_ARGUMENT", "Choose a supported STITCH++ language with the stitch setup profile", exitCode: 2)
        }
        let files = FileManager.default
        let workspace: URL
        do { workspace = try WorkspaceSelection.resolve(options["--workspace"]) }
        catch let problem as InvarError where options["--workspace"] == nil && problem.code == "WORKSPACE_REQUIRED" {
            workspace = URL(fileURLWithPath: files.currentDirectoryPath).resolvingSymlinksInPath()
        }
        let base = options["--tool-root"].map { URL(fileURLWithPath: $0) }
            ?? files.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/invar/tools")
        try files.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let provider = SetupTools(root: base.resolvingSymlinksInPath())
        let lock = Darwin.open(provider.root.appendingPathComponent("setup.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw InvarError("TOOL_SETUP_FAILED", "Cannot open tool setup lock", exitCode: 6) }
        defer { close(lock) }
        while flock(lock, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw InvarError("TOOL_SETUP_FAILED", "Cannot acquire tool setup lock", exitCode: 6)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        var results: [Readiness] = []
        for profile in Profile.allCases where tools.contains(profile) {
            try Task.checkCancellation()
            FileHandle.standardError.write(Data("Preparing \(profile.rawValue) tools\n".utf8))
            var result = Readiness(profile: profile.rawValue)
            do {
                switch profile {
                case .formal: result.paths = try await provider.formal(workspace: workspace)
                case .formalCLI: result.paths = try await provider.formalCLI()
                case .deslop: result.paths = try await provider.deslop()
                case .stitch:
                    result.paths = try await provider.stitch()
                    if let language, let executable = result.paths["stitch"] {
                        result.image = try await provider.prepareStitchImage(executable, language: language)
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { result.diagnostic = String(describing: error) }
            results.append(result)
        }
        let data = try Canonical.encode(results)
        return (data, results.allSatisfy(\.ready) ? 0 : 6)
    }
}
