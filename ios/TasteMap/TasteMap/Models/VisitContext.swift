import Foundation

enum VisitVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case `private`
    case friends
    case `public`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .private: "仅自己"
        case .friends: "互相关注"
        case .public: "公开"
        }
    }

    var detail: String {
        switch self {
        case .private: "只有你能看到"
        case .friends: "互相关注的用户可见"
        case .public: "可能出现在发现和公开资料"
        }
    }

    var systemImage: String {
        switch self {
        case .private: "lock.fill"
        case .friends: "person.2.fill"
        case .public: "globe.asia.australia.fill"
        }
    }
}

enum VisitPaymentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case aa
    case myTreat = "my_treat"
    case treated
    case separate
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aa: "AA"
        case .myTreat: "我请客"
        case .treated: "别人请客"
        case .separate: "各付各的"
        case .other: "其他"
        }
    }
}

enum VisitQueueDuration: String, Codable, CaseIterable, Identifiable, Sendable {
    case noWait = "none"
    case under15
    case under30
    case under60
    case under90
    case under120
    case over120

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noWait: "无需排队"
        case .under15: "15 分钟以内"
        case .under30: "30 分钟以内"
        case .under60: "1 小时以内"
        case .under90: "1.5 小时以内"
        case .under120: "2 小时以内"
        case .over120: "超过 2 小时"
        }
    }

    var approximateMinutes: Int {
        switch self {
        case .noWait: 0
        case .under15: 8
        case .under30: 23
        case .under60: 45
        case .under90: 75
        case .under120: 105
        case .over120: 135
        }
    }
}

enum VisitDiningOccasion: String, Codable, CaseIterable, Identifiable, Sendable {
    case solo
    case date
    case friends
    case family
    case business
    case celebration
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solo: "一个人"
        case .date: "约会"
        case .friends: "朋友聚餐"
        case .family: "家庭聚餐"
        case .business: "商务"
        case .celebration: "庆祝"
        case .other: "自定义"
        }
    }
}

enum VisitNoiseLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case quiet
    case normal
    case loud
    case veryLoud = "very_loud"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .quiet: "安静"
        case .normal: "正常"
        case .loud: "较吵"
        case .veryLoud: "很吵"
        }
    }
}

enum VisitDiningDuration: String, Codable, CaseIterable, Identifiable, Sendable {
    case under15
    case under30
    case under45
    case under60
    case under90
    case under120
    case over120

    var id: String { rawValue }
    var title: String {
        switch self {
        case .under15: "15 分钟以内"
        case .under30: "30 分钟以内"
        case .under45: "45 分钟以内"
        case .under60: "1 小时以内"
        case .under90: "1.5 小时以内"
        case .under120: "2 小时以内"
        case .over120: "超过 2 小时"
        }
    }
}

enum VisitPortionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case normal
    case generous

    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "偏少"
        case .normal: "正常"
        case .generous: "很足"
        }
    }
}

enum VisitTransportConvenience: String, Codable, CaseIterable, Identifiable, Sendable {
    case veryConvenient = "very_convenient"
    case convenient
    case normal
    case inconvenient

    var id: String { rawValue }
    var title: String {
        switch self {
        case .veryConvenient: "很方便"
        case .convenient: "比较方便"
        case .normal: "一般"
        case .inconvenient: "不方便"
        }
    }
}

enum VisitContextOptions {
    static let valueTags = ["偏贵", "合理", "划算", "超值"]
    static let environmentTags = ["安静", "热闹", "舒适", "拥挤", "宽敞", "精致", "有氛围", "景观好"]
    static let serviceTags = ["热情", "周到", "主动", "专业", "高效", "冷淡", "缓慢", "打扰过多"]
}

enum VisitStringArrayStorage {
    static func decode(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return normalized(decoded)
    }

    static func encode(_ values: [String]) -> String {
        let normalized = normalized(values)
        guard let data = try? JSONEncoder().encode(normalized),
              let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }

    static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}

extension Visit {
    var diningOccasionDisplayTitles: [String] {
        diningOccasions.map { occasion in
            if occasion == .other, let diningOccasionText, !diningOccasionText.isEmpty {
                return diningOccasionText
            }
            return occasion.title
        }
    }

    var compactContextSummary: [String] {
        var values = Array(diningOccasionDisplayTitles.prefix(2))
        if let queueDuration { values.append(queueDuration.title) }
        return values
    }
}
