import Foundation
import MCPSkills
import VerificationCore

package enum BundledSkills {
    package static func catalog(beside executable: URL) throws -> SkillCatalog {
        let bundleURL = executable.deletingLastPathComponent().appendingPathComponent("Invar_InvarSkills.bundle")
        guard let directory = Bundle(url: bundleURL)?.url(forResource: "skills", withExtension: nil) else {
            throw InvarError("SKILLS_UNAVAILABLE", "The Invar installation is missing its bundled skills", exitCode: 3)
        }

        // Reserve framing space even if JSON escapes every byte of a skill file.
        let options = SkillCatalog.Options(
            baseURI: "skill://invar",
            limits: .init(maxFiles: SkillLimits.specification.maxFiles, maxBytes: 131_072)
        )
        let catalog = try SkillCatalog(directory: directory, options: options)
        guard !catalog.skills.isEmpty else {
            throw InvarError("SKILLS_UNAVAILABLE", "The Invar installation has an empty skill catalog", exitCode: 3)
        }
        return catalog
    }
}
