import Foundation

nonisolated enum PremiumFeature: String, CaseIterable, Codable, Identifiable, Sendable {
    case fullTasteProfile = "full_taste_profile"
    case companionAnalysis = "companion_analysis"
    case recommendationSourceAnalysis = "recommendation_source_analysis"
    case similarTaste = "similar_taste"
    case deepRecommendation = "deep_recommendation"
    case advancedRecommendationFilters = "advanced_recommendation_filters"
    case monthlyRecap = "monthly_review"
    case annualRecap = "annual_review"
    case spendingInsights = "spending_insights"
    case companionRecommendation = "companion_recommendation"
    case customAvatar = "custom_avatar"
    case expandedVisitPhotos = "visit_photo_limit"

    var id: String { rawValue }

    var definition: PremiumFeatureDefinition {
        PremiumFeatureRegistry.definition(for: self)
    }
}

nonisolated struct PremiumFeatureDefinition: Equatable, Sendable {
    let feature: PremiumFeature
    let title: String
    let valueDescription: String
    let symbol: String
    let posterProtected: Bool
}

nonisolated enum PremiumFeatureRegistry {
    static let definitions: [PremiumFeatureDefinition] = [
        .init(feature: .fullTasteProfile, title: "完整口味档案", valueDescription: "看懂长期偏好、预算、场景与评分风格", symbol: "fork.knife", posterProtected: true),
        .init(feature: .companionAnalysis, title: "饭搭子分析", valueDescription: "回看你和谁最常吃、最合拍", symbol: "person.2.fill", posterProtected: true),
        .init(feature: .recommendationSourceAnalysis, title: "推荐来源分析", valueDescription: "验证谁的推荐真正适合你", symbol: "text.bubble.fill", posterProtected: true),
        .init(feature: .similarTaste, title: "同味能力", valueDescription: "查看同味之选、同味评分与相似口味线索", symbol: "person.2.wave.2", posterProtected: false),
        .init(feature: .deepRecommendation, title: "深度个性化推荐", valueDescription: "看到更完整的推荐依据与解释", symbol: "sparkles", posterProtected: false),
        .init(feature: .advancedRecommendationFilters, title: "高级推荐筛选", valueDescription: "按推荐来源、场景和饭搭子继续筛选", symbol: "line.3.horizontal.decrease.circle", posterProtected: false),
        .init(feature: .monthlyRecap, title: "本月回顾", valueDescription: "把当月味觉记忆整理成完整回顾", symbol: "calendar", posterProtected: true),
        .init(feature: .annualRecap, title: "年度食味年鉴", valueDescription: "回看全年餐桌、城市与口味变化", symbol: "calendar.badge.clock", posterProtected: true),
        .init(feature: .spendingInsights, title: "消费洞察", valueDescription: "理解真实消费区间与长期变化", symbol: "receipt", posterProtected: true),
        .init(feature: .companionRecommendation, title: "饭搭子选餐", valueDescription: "结合共同记录选择下一家餐厅", symbol: "person.2.badge.gearshape", posterProtected: false),
        .init(feature: .customAvatar, title: "自定义头像", valueDescription: "使用自己的照片作为个人头像", symbol: "person.crop.circle.badge.plus", posterProtected: false),
        .init(feature: .expandedVisitPhotos, title: "更多到访照片", valueDescription: "每次到访从 3 张提升到 20 张", symbol: "photo.stack.fill", posterProtected: false),
    ]

    static func definition(for feature: PremiumFeature) -> PremiumFeatureDefinition {
        switch feature {
        case .fullTasteProfile: definitions[0]
        case .companionAnalysis: definitions[1]
        case .recommendationSourceAnalysis: definitions[2]
        case .similarTaste: definitions[3]
        case .deepRecommendation: definitions[4]
        case .advancedRecommendationFilters: definitions[5]
        case .monthlyRecap: definitions[6]
        case .annualRecap: definitions[7]
        case .spendingInsights: definitions[8]
        case .companionRecommendation: definitions[9]
        case .customAvatar: definitions[10]
        case .expandedVisitPhotos: definitions[11]
        }
    }

    static let paywallHighlights: [PremiumFeature] = [
        .fullTasteProfile, .deepRecommendation, .similarTaste,
        .companionAnalysis, .monthlyRecap, .expandedVisitPhotos,
    ]
}

nonisolated enum PremiumProtectedOperation: String, Sendable {
    case view
    case analyze
    case posterRender
    case posterSave
    case posterShare
    case deepLink
}

nonisolated enum PremiumAccessDecision: Equatable, Sendable {
    case allowed
    case denied
    case loading
}

nonisolated enum PremiumFeatureAccessPolicy {
    static func decision(
        for feature: PremiumFeature,
        operation: PremiumProtectedOperation = .view,
        membershipStatus: MembershipStatus
    ) -> PremiumAccessDecision {
        switch membershipStatus {
        case .premium, .gracePeriod:
            return .allowed
        case .loading, .unknown:
            return .loading
        case .free, .expired:
            return .denied
        }
    }

    static func visitPhotoLimit(membershipStatus: MembershipStatus) -> Int {
        switch membershipStatus {
        case .premium, .gracePeriod: 20
        case .loading, .unknown, .free, .expired: 3
        }
    }
}

nonisolated enum MembershipStatus: String, Codable, CaseIterable, Sendable {
    case loading
    case unknown
    case free
    case premium
    case expired
    case gracePeriod = "grace_period"
}

nonisolated enum PremiumEntrySource: Hashable, Identifiable, Sendable {
    case profile
    case settings
    case feature(PremiumFeature)

    var id: String {
        switch self {
        case .profile: "profile_entry"
        case .settings: "settings_entry"
        case .feature(let feature): feature.rawValue
        }
    }

    var contextCopy: String {
        switch self {
        case .profile: "查看完整会员能力。"
        case .settings: "查看会员状态与未来购买入口。"
        case .feature(let feature): feature.definition.valueDescription
        }
    }
}
