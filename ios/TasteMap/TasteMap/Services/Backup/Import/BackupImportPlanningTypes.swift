import Foundation

nonisolated enum BackupImportEntityKind: String, Codable, CaseIterable, Sendable {
    case restaurant, visit, dish, visitDish, photo, companion
    case recommendationSource, profile, restaurantList, restaurantListItem

    var title: String {
        switch self {
        case .restaurant: "餐厅"
        case .visit: "到访"
        case .dish: "菜品"
        case .visitDish: "菜品关联"
        case .photo: "照片记录"
        case .companion: "饭搭子"
        case .recommendationSource: "推荐来源"
        case .profile: "个人资料"
        case .restaurantList: "榜单"
        case .restaurantListItem: "榜单条目"
        }
    }
}

nonisolated struct BackupImportSourcePlaceIdentity: Codable, Equatable, Hashable, Sendable {
    let provider: String
    let externalID: String
    let isPrimary: Bool

    var key: String { "\(provider):\(externalID)" }
}

nonisolated struct BackupImportSourceRestaurant: Codable, Equatable, Sendable {
    let sourceID: String
    let placeIdentities: [BackupImportSourcePlaceIdentity]
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let status: String
    let preferenceLevel: String
    let overallRating: Double?
    let foodRating: Double?
    let environmentRating: Double?
    let serviceRating: Double?
    let valueRating: Double?
    let tags: [String]
    let longTermNote: String
    let pricePerPerson: Decimal?
    let phone: String?
    let openingHours: String?
    let markerType: String
    let markerPhotoSourceID: String?
    let merchantImageURL: String?
    let markerEmoji: String
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceVisit: Codable, Equatable, Sendable {
    let sourceID: String
    let sourceRestaurantID: String
    let visitedAt: Date
    let diningMode: String
    let visibility: String
    let partySize: Int?
    let totalPrice: Decimal?
    let myActualSpend: Decimal?
    let paymentMode: String?
    let pricePerPerson: Decimal?
    let queueDuration: String?
    let diningOccasions: [String]
    let diningOccasionText: String?
    let rating: Double?
    let valueRating: Double?
    let environmentRating: Double?
    let serviceRating: Double?
    let valueTags: [String]
    let environmentTags: [String]
    let serviceTags: [String]
    let noiseLevel: String?
    let diningDuration: String?
    let portionLevel: String?
    let transportConvenience: String?
    let specialNotes: String?
    let companionSourceIDs: [String]
    let recommendationSourceID: String?
    let recommendationSourceType: String?
    let recommendationSourceText: String?
    let note: String?
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceDish: Codable, Equatable, Sendable {
    let sourceID: String
    let sourceRestaurantID: String
    let sourceVisitID: String
    let name: String
    let taste: String
    let rating: Double?
    let price: Decimal?
    let sourcePhotoID: String?
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceVisitDish: Codable, Equatable, Sendable {
    let sourceID: String
    let sourceRestaurantID: String
    let sourceVisitID: String
    let sourceDishID: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceCompanion: Codable, Equatable, Sendable {
    let sourceID: String
    let displayName: String
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceRecommendationSource: Codable, Equatable, Sendable {
    let sourceID: String
    let displayName: String
    let sourceType: String
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceProfile: Codable, Equatable, Sendable {
    let sourceID: String
    let displayName: String
    let bio: String
    let city: String
    let avatarPhotoSourceID: String?
    let avatarPresetID: String
    let visibility: String
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourcePhoto: Codable, Equatable, Sendable {
    let sourceID: String
    let parentEntityType: String
    let parentSourceID: String
    let kind: String
    let fileName: String?
    let mimeType: String
    let byteSize: Int64
    let width: Int?
    let height: Int?
    let sortOrder: Int
    let visibility: String
    let createdAt: Date
    let updatedAt: Date
    let binaryAvailable: Bool
}

nonisolated struct BackupImportSourceRestaurantList: Codable, Equatable, Sendable {
    let sourceID: String
    let title: String
    let listDescription: String
    let visibility: String
    let isRanked: Bool
    let coverMode: String
    let customCoverPhotoSourceID: String?
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceRestaurantListItem: Codable, Equatable, Sendable {
    let sourceID: String
    let sourceListID: String
    let sourceRestaurantID: String
    let position: Int
    let note: String
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BackupImportSourceTombstone: Codable, Equatable, Sendable {
    let entityType: BackupImportEntityKind
    let sourceID: String
    let deletedAt: Date
}

nonisolated struct BackupImportSourceGraph: Codable, Equatable, Sendable {
    let sourceFileSHA256: String
    let sourceFormat: BackupImportSourceFormat
    let restaurants: [BackupImportSourceRestaurant]
    let visits: [BackupImportSourceVisit]
    let dishes: [BackupImportSourceDish]
    let visitDishes: [BackupImportSourceVisitDish]
    let photos: [BackupImportSourcePhoto]
    let companions: [BackupImportSourceCompanion]
    let recommendationSources: [BackupImportSourceRecommendationSource]
    let profiles: [BackupImportSourceProfile]
    let restaurantLists: [BackupImportSourceRestaurantList]
    let restaurantListItems: [BackupImportSourceRestaurantListItem]
    let tombstones: [BackupImportSourceTombstone]
}

nonisolated enum BackupImportPlanActionKind: String, Codable, CaseIterable, Sendable {
    case create
    case exactDuplicate
    case exactMerge
    case userReviewRequired
    case skip
    case blocked
}

nonisolated struct BackupImportPlannedAction: Codable, Equatable, Identifiable, Sendable {
    let entityType: BackupImportEntityKind
    let sourceID: String
    let targetID: String?
    let matchedLocalID: String?
    let action: BackupImportPlanActionKind
    let reasonCode: String
    let safeLabel: String
    let dependencySourceIDs: [String]

    var id: String { "\(entityType.rawValue):\(sourceID)" }
}

nonisolated enum BackupImportReviewOptionKind: String, Codable, Sendable {
    case merge, create, skip, keepCurrent, useBackup
}

nonisolated struct BackupImportReviewOption: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: BackupImportReviewOptionKind
    let title: String
    let targetID: String?
}

nonisolated struct ImportPlanReviewItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let entityType: BackupImportEntityKind
    let sourceID: String
    let title: String
    let sourceSafeLabel: String
    let candidateSafeLabel: String?
    let reason: String
    let detail: String?
    let options: [BackupImportReviewOption]
    let recommendedOptionID: String
}

nonisolated struct BackupImportReviewDecision: Codable, Equatable, Sendable {
    let reviewItemID: String
    let selectedOptionID: String
    let sourceFileSHA256: String
    let sourceID: String
    let targetID: String?
    let localSnapshotRevision: String
}

nonisolated struct BackupImportEntityActionSummary: Codable, Equatable, Sendable {
    let entityType: BackupImportEntityKind
    let create: Int
    let exactMerge: Int
    let exactDuplicate: Int
    let review: Int
    let skipped: Int
    let blocked: Int
}

nonisolated struct BackupImportPlanSummary: Codable, Equatable, Sendable {
    let entities: [BackupImportEntityActionSummary]
    let estimatedMutationCount: Int
    let warningCount: Int
    let reviewCount: Int
    let blockerCount: Int
}

nonisolated struct BackupImportPlanTiming: Codable, Equatable, Sendable {
    let snapshotSeconds: Double
    let matchingSeconds: Double
    let totalSeconds: Double
}

nonisolated struct BackupImportPlan: Codable, Sendable {
    let planID: UUID
    let sourceFileSHA256: String
    let sourceFormat: BackupImportSourceFormat
    let currentTasteMapUserID: String
    let generatedAt: Date
    let localSnapshotRevision: String
    let actions: [BackupImportPlannedAction]
    let reviewItems: [ImportPlanReviewItem]
    let warnings: [String]
    let summary: BackupImportPlanSummary
    let timing: BackupImportPlanTiming

    var canBeConfirmed: Bool {
        summary.blockerCount == 0 && reviewItems.isEmpty
    }
}

extension BackupImportPlan: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.planID == rhs.planID
            && lhs.sourceFileSHA256 == rhs.sourceFileSHA256
            && lhs.sourceFormat == rhs.sourceFormat
            && lhs.currentTasteMapUserID == rhs.currentTasteMapUserID
            && lhs.localSnapshotRevision == rhs.localSnapshotRevision
            && lhs.actions == rhs.actions
            && lhs.reviewItems == rhs.reviewItems
            && lhs.warnings == rhs.warnings
            && lhs.summary == rhs.summary
    }
}

nonisolated struct ConfirmedBackupImportPlan: Equatable, Sendable {
    let plan: BackupImportPlan
    let sourceGraph: BackupImportSourceGraph
    let decisions: [BackupImportReviewDecision]
}

nonisolated enum BackupImportPlanningError: Error, Equatable, LocalizedError, Sendable {
    case invalidCurrentUser
    case preflightBlocked
    case sourceHashMismatch
    case ambiguousLocalOwnership(entityType: BackupImportEntityKind, entityID: String)
    case invalidLocalRecord(entityType: BackupImportEntityKind, entityID: String)
    case unresolvedReview(String)
    case planStale
    case userChanged
    case invalidDecision
    case transactionFailed
    #if DEBUG
    case injectedFailure(String)
    #endif

    var errorDescription: String? {
        switch self {
        case .invalidCurrentUser: "当前 Taste Map 用户身份无效。"
        case .preflightBlocked: "文件仍有预检阻塞问题，不能生成匹配计划。"
        case .sourceHashMismatch: "文件内容已变化，需要重新预检。"
        case let .ambiguousLocalOwnership(type, id):
            "本地 \(type.title) \(id) 的归属仍是 local，无法安全参与匹配。"
        case let .invalidLocalRecord(type, id): "本地 \(type.title) \(id) 无法建立安全快照。"
        case .unresolvedReview: "匹配计划仍有尚未确认的项目。"
        case .planStale: "本地数据已经变化，请重新生成匹配计划。"
        case .userChanged: "当前登录账户已变化，请重新生成匹配计划。"
        case .invalidDecision: "匹配决定与当前文件或本地快照不一致。"
        case .transactionFailed: "本地导入事务失败，未保留任何部分数据。"
        #if DEBUG
        case let .injectedFailure(stage): "测试在 \(stage) 阶段注入失败。"
        #endif
        }
    }
}
