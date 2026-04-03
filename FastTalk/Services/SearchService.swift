import Foundation
import SwiftData

enum SearchService {
    static func search(query: String, in context: ModelContext) -> [Skill] {
        guard !query.isEmpty else { return [] }

        let descriptor = FetchDescriptor<Skill>()
        guard let allSkills = try? context.fetch(descriptor) else { return [] }

        return allSkills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query) ||
            skill.skillDescription.localizedCaseInsensitiveContains(query) ||
            skill.content.localizedCaseInsensitiveContains(query)
        }
    }
}
