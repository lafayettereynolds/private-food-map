import Foundation

/// Shared filter identity/presentation only; the original Restaurant.city is
/// retained for storage, detail display, sync and export.
enum RestaurantCityFilterIdentity {
    static func key(_ value: String) -> String {
        label(value).lowercased(with: Locale(identifier: "zh_CN"))
    }

    static func matches(_ left: String, _ right: String) -> Bool {
        key(left) == key(right)
    }

    static func options(_ values: [String]) -> [String] {
        var labels: [String: String] = [:]
        for value in values {
            let display = label(value)
            let identity = key(display)
            guard !identity.isEmpty else { continue }
            if labels[identity] == nil || display < labels[identity]! { labels[identity] = display }
        }
        return labels.values.sorted {
            $0.compare($1, locale: Locale(identifier: "zh_CN")) == .orderedAscending
        }
    }

    private static func label(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            // Only the administrative suffix 市 is optional. Do not truncate
            // genuine names such as 杭州/温州 or overseas names such as Kansas City.
            .replacingOccurrences(of: #"^([\p{Han}]{2,})市$"#, with: "$1", options: .regularExpression)
    }
}
