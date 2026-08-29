import Foundation

nonisolated struct BackupExportValidationIssue: Equatable, Sendable {
    enum Code: String, Equatable, Sendable {
        case unauthenticated
        case invalidCurrentUser
        case ambiguousLocalOwnership
        case unverifiedOwner
        case invalidField
        case invalidRelationship
        case duplicateStableID
        case orphanedReference
        case unsafePhotoMetadata
        case integrityMismatch
    }

    let code: Code
    let entityType: BackupEntityTypeV1?
    let entityID: String?
    let field: String?
    let referenceID: String?
    let message: String
}

nonisolated struct BackupExportValidationError: Error, Equatable, LocalizedError, Sendable {
    let issues: [BackupExportValidationIssue]

    var errorDescription: String? {
        guard let first = issues.first else { return "备份数据验证失败。" }
        if issues.count == 1 { return first.message }
        return "备份数据验证失败：\(first.message)（另有 \(issues.count - 1) 项）"
    }
}

nonisolated enum BackupExportError: Error, Equatable, LocalizedError, Sendable {
    case unauthenticated
    case invalidCurrentUser
    case invalidSource
    case invalidMoney(entityType: BackupEntityTypeV1, entityID: String, field: String)
    case invalidTimestamp(entityType: BackupEntityTypeV1, entityID: String, field: String)
    case invalidRating(entityType: BackupEntityTypeV1, entityID: String, field: String)
    case invalidRestaurantRecord(entityID: String)
    case invalidListSnapshot(entityID: String)
    case validation(BackupExportValidationError)
    case encodingFailed
    case integrityMismatch
    case temporaryFileFailed

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            "请先登录 Taste Map，再导出当前账号的备份。"
        case .invalidCurrentUser:
            "当前 Taste Map 用户身份无效，无法安全导出。"
        case .invalidSource:
            "无法确定当前 App 版本或环境。"
        case .invalidMoney(_, _, let field):
            "金额字段 \(field) 不是 Backup v1 支持的非负两位小数。"
        case .invalidTimestamp(_, _, let field):
            "时间字段 \(field) 无法转换为 Backup v1 UTC 时间。"
        case .invalidRating(_, _, let field):
            "评分字段 \(field) 不是 0.5 到 5.0 的半星值。"
        case .invalidRestaurantRecord:
            "餐厅扩展数据无法安全映射到 Backup v1。"
        case .invalidListSnapshot:
            "榜单餐厅快照无效，无法生成可恢复的备份。"
        case .validation(let error):
            error.errorDescription
        case .encodingFailed:
            "Backup v1 JSON 生成失败。"
        case .integrityMismatch:
            "Backup v1 完整性校验失败。"
        case .temporaryFileFailed:
            "无法创建受保护的临时备份文件。"
        }
    }
}

nonisolated struct BackupExportSourceInfo: Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let environment: TasteMapAppEnvironment

    init(appVersion: String, appBuild: String, environment: TasteMapAppEnvironment) throws {
        let version = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = appBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty, version.count <= 64, !build.isEmpty, build.count <= 64 else {
            throw BackupExportError.invalidSource
        }
        self.appVersion = version
        self.appBuild = build
        self.environment = environment
    }

    static func current(bundle: Bundle = .main) throws -> Self {
        try Self(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            environment: .current
        )
    }

    var contractValue: BackupSourceV1 {
        BackupSourceV1(
            platform: .ios,
            appVersion: appVersion,
            appBuild: appBuild,
            environment: environment == .development ? .development : .production
        )
    }
}

nonisolated struct BackupExportArtifact: Identifiable, Sendable {
    let id: UUID
    let fileURL: URL
    let exportedAt: Date
    let metadata: BackupMetadataV1
}

@MainActor
struct BackupExportInput {
    let restaurants: [Restaurant]
    let visits: [Visit]
    let dishes: [Dish]
    let visitDishes: [VisitDish]
    let photos: [PhotoAsset]
    let companions: [DiningCompanion]
    let recommendationSources: [RecommendationSource]
    let profiles: [UserProfile]
    let restaurantLists: [RestaurantList]
    let restaurantListItems: [RestaurantListItem]
}
