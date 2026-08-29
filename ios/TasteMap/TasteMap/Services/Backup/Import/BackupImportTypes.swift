import Foundation

nonisolated enum BackupImportSourceFormat: String, Codable, CaseIterable, Sendable {
    case backupV1 = "backup-v1"
    case legacyWebV4 = "legacy-web-v4"

    var title: String {
        switch self {
        case .backupV1: "Taste Map Backup v1"
        case .legacyWebV4: "Legacy Web v4"
        }
    }
}

nonisolated enum BackupImportIssueSeverity: String, Codable, CaseIterable, Sendable {
    case blocking
    case requiresReview
    case warning
    case info

    var sortOrder: Int {
        switch self {
        case .blocking: 0
        case .requiresReview: 1
        case .warning: 2
        case .info: 3
        }
    }

    var title: String {
        switch self {
        case .blocking: "无法继续"
        case .requiresReview: "需要确认"
        case .warning: "可以继续"
        case .info: "信息"
        }
    }
}

nonisolated enum BackupImportIssueCategory: String, Codable, Sendable {
    case fileSafety
    case schema
    case integrity
    case metadata
    case reference
    case tombstone
    case normalization
    case deprecatedField
    case securityAuthority
    case unsupportedData
    case photoBinary
    case socialAuthority
    case informational
}

nonisolated struct BackupImportIssue: Identifiable, Codable, Equatable, Sendable {
    let severity: BackupImportIssueSeverity
    let category: BackupImportIssueCategory
    let code: String
    let title: String
    let explanation: String
    let entityType: String?
    let sourceReference: String?
    let field: String?
    let count: Int

    init(
        severity: BackupImportIssueSeverity,
        category: BackupImportIssueCategory,
        code: String,
        title: String,
        explanation: String,
        entityType: String? = nil,
        sourceReference: String? = nil,
        field: String? = nil,
        count: Int = 1
    ) {
        self.severity = severity
        self.category = category
        self.code = code
        self.title = title
        self.explanation = explanation
        self.entityType = entityType
        self.sourceReference = sourceReference
        self.field = field
        self.count = max(1, count)
    }

    var id: String {
        [
            String(severity.sortOrder), category.rawValue, code,
            entityType ?? "", field ?? "", sourceReference ?? "", String(count),
        ].joined(separator: "|")
    }

    var stableSortKey: String { id }
}

nonisolated struct BackupImportEntityCounts: Codable, Equatable, Sendable {
    let restaurants: Int
    let visits: Int
    let dishes: Int
    let visitDishes: Int
    let photos: Int
    let companions: Int
    let recommendationSources: Int
    let profiles: Int
    let restaurantLists: Int
    let restaurantListItems: Int
    let tombstones: Int

    var total: Int {
        restaurants + visits + dishes + visitDishes + photos + companions
            + recommendationSources + profiles + restaurantLists + restaurantListItems
            + tombstones
    }
}

nonisolated struct BackupImportSourceMetadata: Codable, Equatable, Sendable {
    let exportedAt: String?
    let sourceApp: String
    let sourceEnvironment: String?
    let sourceDatabase: String?
}

nonisolated enum BackupImportPhotoBinaryStatus: String, Codable, Sendable {
    case metadataOnlyBackupV1
    case partialLegacyMetadataOnly

    var message: String {
        switch self {
        case .metadataOnlyBackupV1:
            "此备份不包含照片原图。"
        case .partialLegacyMetadataOnly:
            "旧 Web 备份只包含部分照片元数据，无法仅凭该文件恢复照片原图。"
        }
    }
}

nonisolated struct BackupImportGraphSummary: Codable, Equatable, Sendable {
    let totalEntities: Int
    let relationshipCount: Int
    let providerIdentityCount: Int
    let normalizedTombstoneCount: Int
}

nonisolated struct ImportPreflightResult: Codable, Sendable {
    let sourceFormat: BackupImportSourceFormat
    let sourceVersion: Int
    let fileName: String
    let fileSize: Int
    let sourceFileSHA256: String
    let backupIntegritySHA256: String?
    let inspectedAt: Date
    let sourceMetadata: BackupImportSourceMetadata
    let counts: BackupImportEntityCounts
    let securityDiscardCount: Int
    let deprecatedFieldCount: Int
    let unsupportedCount: Int
    let photoBinaryStatus: BackupImportPhotoBinaryStatus
    let issues: [BackupImportIssue]
    let graphSummary: BackupImportGraphSummary

    init(
        sourceFormat: BackupImportSourceFormat,
        sourceVersion: Int,
        fileName: String,
        fileSize: Int,
        sourceFileSHA256: String,
        backupIntegritySHA256: String?,
        inspectedAt: Date,
        sourceMetadata: BackupImportSourceMetadata,
        counts: BackupImportEntityCounts,
        securityDiscardCount: Int,
        deprecatedFieldCount: Int,
        unsupportedCount: Int,
        photoBinaryStatus: BackupImportPhotoBinaryStatus,
        issues: [BackupImportIssue],
        graphSummary: BackupImportGraphSummary
    ) {
        self.sourceFormat = sourceFormat
        self.sourceVersion = sourceVersion
        self.fileName = fileName
        self.fileSize = fileSize
        self.sourceFileSHA256 = sourceFileSHA256
        self.backupIntegritySHA256 = backupIntegritySHA256
        self.inspectedAt = inspectedAt
        self.sourceMetadata = sourceMetadata
        self.counts = counts
        self.securityDiscardCount = securityDiscardCount
        self.deprecatedFieldCount = deprecatedFieldCount
        self.unsupportedCount = unsupportedCount
        self.photoBinaryStatus = photoBinaryStatus
        self.issues = issues.sorted { $0.stableSortKey < $1.stableSortKey }
        self.graphSummary = graphSummary
    }

    var warningCount: Int { issueCount(.warning) }
    var reviewCount: Int { issueCount(.requiresReview) }
    var blockingCount: Int { issueCount(.blocking) }
    var canProceedToPlanning: Bool { blockingCount == 0 }

    func issues(with severity: BackupImportIssueSeverity) -> [BackupImportIssue] {
        issues.filter { $0.severity == severity }
    }

    private func issueCount(_ severity: BackupImportIssueSeverity) -> Int {
        issues.filter { $0.severity == severity }.reduce(0) { $0 + $1.count }
    }
}

extension ImportPreflightResult: Equatable {
    // Inspection time is observational metadata. The same bytes must otherwise
    // produce the same result on every run.
    nonisolated static func == (lhs: ImportPreflightResult, rhs: ImportPreflightResult) -> Bool {
        lhs.sourceFormat == rhs.sourceFormat
            && lhs.sourceVersion == rhs.sourceVersion
            && lhs.fileName == rhs.fileName
            && lhs.fileSize == rhs.fileSize
            && lhs.sourceFileSHA256 == rhs.sourceFileSHA256
            && lhs.backupIntegritySHA256 == rhs.backupIntegritySHA256
            && lhs.sourceMetadata == rhs.sourceMetadata
            && lhs.counts == rhs.counts
            && lhs.securityDiscardCount == rhs.securityDiscardCount
            && lhs.deprecatedFieldCount == rhs.deprecatedFieldCount
            && lhs.unsupportedCount == rhs.unsupportedCount
            && lhs.photoBinaryStatus == rhs.photoBinaryStatus
            && lhs.issues == rhs.issues
            && lhs.graphSummary == rhs.graphSummary
    }
}

nonisolated struct BackupImportPreflightTiming: Equatable, Sendable {
    let fileReadSeconds: Double
    let inspectionSeconds: Double
    let decodeAndNormalizeSeconds: Double
    let validationSeconds: Double
    let totalSeconds: Double
}

nonisolated struct BackupImportPreflightRun: Equatable, Sendable {
    let result: ImportPreflightResult
    let timing: BackupImportPreflightTiming
}

nonisolated enum BackupImportProgressStage: String, CaseIterable, Sendable {
    case reading
    case inspecting
    case decoding
    case validating
    case summarizing

    var title: String {
        switch self {
        case .reading: "正在读取文件…"
        case .inspecting: "正在检查格式…"
        case .decoding: "正在检查内容…"
        case .validating: "正在验证完整性…"
        case .summarizing: "正在生成预览…"
        }
    }
}

nonisolated enum BackupImportPreflightError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case localFileRequired
    case unreadableFile
    case fileTooLarge(maximumBytes: Int)
    case invalidUTF8
    case malformedJSON
    case rootMustBeObject
    case excessiveNesting(maximumDepth: Int)
    case invalidNumber
    case stringLimitExceeded(field: String, maximumBytes: Int)
    case collectionLimitExceeded(collection: String, maximum: Int)
    case totalEntityLimitExceeded(maximum: Int)
    case unsupportedFormat
    case invalidBackupV1Format
    case invalidBackupV1Version
    case invalidLegacyApp
    case invalidLegacyVersion
    case backupV1DecodeFailed
    case legacyV4DecodeFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: "已取消检查，未保留文件或数据。"
        case .localFileRequired: "请选择 Files 或文件提供方中的 JSON 文档；不支持远程 URL。"
        case .unreadableFile: "无法安全读取这个文件。"
        case let .fileTooLarge(maximum):
            "文件超过 \(ByteCountFormatter.string(fromByteCount: Int64(maximum), countStyle: .file)) 上限。"
        case .invalidUTF8: "文件不是有效的 UTF-8 JSON。"
        case .malformedJSON: "JSON 格式无效，文件可能不完整或已损坏。"
        case .rootMustBeObject: "备份 JSON 的根节点必须是对象，不能是数组或单个值。"
        case let .excessiveNesting(maximum): "JSON 嵌套超过安全上限 \(maximum) 层。"
        case .invalidNumber: "JSON 中包含不支持的数字。"
        case let .stringLimitExceeded(field, maximum):
            "字段“\(field)”超过安全长度上限 \(maximum) bytes。"
        case let .collectionLimitExceeded(collection, maximum):
            "集合“\(collection)”超过安全数量上限 \(maximum)。"
        case let .totalEntityLimitExceeded(maximum): "文件中的记录总数超过安全上限 \(maximum)。"
        case .unsupportedFormat: "无法识别这个文件。请选择 Taste Map Backup v1 或 Legacy Web v4 JSON。"
        case .invalidBackupV1Format: "Backup v1 的 format 不正确。"
        case .invalidBackupV1Version: "当前版本不支持这个 Backup schemaVersion。"
        case .invalidLegacyApp: "Legacy 文件不是 Taste Map Web 备份。"
        case .invalidLegacyVersion: "当前版本只支持 Legacy Web v4。"
        case .backupV1DecodeFailed: "Backup v1 的结构或字段不符合正式合同。"
        case .legacyV4DecodeFailed: "Legacy Web v4 无法建立安全的只读 staging。"
        }
    }
}
