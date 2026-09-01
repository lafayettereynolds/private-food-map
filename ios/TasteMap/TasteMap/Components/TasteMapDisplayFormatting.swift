import Foundation

/// Centralized, user-facing Chinese date presentation. Storage and API dates
/// remain ISO-8601/UTC and are intentionally outside this type.
nonisolated enum TasteMapDisplayDate {
    static let localeIdentifier = "zh_Hans_CN"

    static func abbreviatedDateTime(_ date: Date) -> String {
        string(date, dateStyle: .medium, timeStyle: .short)
    }

    static func abbreviatedDate(_ date: Date) -> String {
        string(date, dateStyle: .medium, timeStyle: .none)
    }

    static func numericDateTime(_ date: Date) -> String {
        string(date, dateStyle: .short, timeStyle: .short)
    }

    static func yearMonth(_ date: Date) -> String {
        templated(date, template: "yMMMM")
    }

    static func monthDay(_ date: Date) -> String {
        templated(date, template: "MMMMd")
    }

    static func relative(_ date: Date, relativeTo referenceDate: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    private static func string(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private static func templated(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
