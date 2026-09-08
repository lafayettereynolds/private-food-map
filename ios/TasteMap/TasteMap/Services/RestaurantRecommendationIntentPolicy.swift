import Foundation

struct RestaurantRecommendationIntentFeedback: Codable, Equatable, Sendable {
    var brandIDs: [String] = []
    var contextCounts: [String: Int] = [:]
}

struct RestaurantRecommendationIntentMetadata: Sendable {
    let aliases: Set<String>
    let name: String
    let tags: [String]
}

struct RestaurantRecommendationIntentVote: Codable, Equatable, Sendable {
    var aliases: Set<String>
    let brandID: String?
    let context: String?
}

/// Conservative recommendation willingness only. Never changes ratings,
/// probability, cuisine preferences, geographic filters or Restaurant records.
enum RestaurantRecommendationIntentPolicy {
    static let contexts: Set<String> = ["everyday_fast_food", "snack_takeaway"]
    static let brands: Set<String> = ["kfc", "mcdonalds", "juewei"]

    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func classify(name: String, tags: [String]) -> (brandID: String?, context: String?) {
        let value = normalized(name)
        let brandPatterns = [("kfc", "^(肯德基|kfc)(?=$|[\\s()·-])"),
                             ("mcdonalds", "^(麦当劳|mcdonald's|mcdonalds)(?=$|[\\s()·-])"),
                             ("juewei", "^绝味鸭脖(?=$|[\\s()·-])")]
        let brand = brandPatterns.first { value.range(of: $0.1, options: .regularExpression) != nil }?.0
        if brand == "kfc" || brand == "mcdonalds" { return (brand, "everyday_fast_food") }
        if brand == "juewei" { return (brand, "snack_takeaway") }
        let normalizedTags = Set(tags.map(normalized))
        let fastFood = !normalizedTags.isDisjoint(with: ["everyday_fast_food", "日常快餐"])
        let snack = !normalizedTags.isDisjoint(with: ["snack_takeaway", "小吃外带"])
        // Conflicting explicit classifications are not evidence for either class.
        return (nil, fastFood == snack ? nil : fastFood ? "everyday_fast_food" : "snack_takeaway")
    }

    static func expand(_ aliases: Set<String>, through groups: [Set<String>]) -> Set<String> {
        var result = aliases
        var previous: Int
        repeat {
            previous = result.count
            for group in groups where !group.isDisjoint(with: result) { result.formUnion(group) }
        } while result.count != previous
        return result
    }

    static func reconcile(_ votes: [RestaurantRecommendationIntentVote], groups: [Set<String>]) -> [RestaurantRecommendationIntentVote] {
        var result: [RestaurantRecommendationIntentVote] = []
        let allGroups = groups + votes.map(\.aliases)
        for vote in votes {
            var next = vote
            next.aliases = expand(vote.aliases, through: allGroups)
            if let index = result.firstIndex(where: { !$0.aliases.isDisjoint(with: next.aliases) }) {
                // Preserve the original feedback, never learn a new category on read.
                result[index].aliases.formUnion(next.aliases)
            } else { result.append(next) }
        }
        return result
    }

    static func feedback(_ votes: [RestaurantRecommendationIntentVote]) -> RestaurantRecommendationIntentFeedback {
        var result = RestaurantRecommendationIntentFeedback()
        result.brandIDs = Array(Set(votes.compactMap(\.brandID).filter(brands.contains))).sorted()
        for context in votes.compactMap(\.context) where contexts.contains(context) {
            result.contextCounts[context, default: 0] += 1
        }
        return result
    }

    static func permits(name: String, tags: [String], feedback: RestaurantRecommendationIntentFeedback) -> Bool {
        guard let brand = classify(name: name, tags: tags).brandID else { return true }
        return !feedback.brandIDs.contains(brand)
    }

    static func deprioritized(name: String, tags: [String], feedback: RestaurantRecommendationIntentFeedback) -> Bool {
        guard let context = classify(name: name, tags: tags).context else { return false }
        return (feedback.contextCounts[context] ?? 0) >= 2
    }

    static func stablePriority<T>(_ values: [T], feedback: RestaurantRecommendationIntentFeedback,
                                  metadata: (T) -> (name: String, tags: [String])) -> [T] {
        let split = values.reduce(into: (preferred: [T](), later: [T]())) { result, value in
            let item = metadata(value)
            if deprioritized(name: item.name, tags: item.tags, feedback: feedback) { result.later.append(value) }
            else { result.preferred.append(value) }
        }
        return split.preferred + split.later
    }
}
