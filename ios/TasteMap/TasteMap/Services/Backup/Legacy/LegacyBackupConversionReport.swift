import Foundation

nonisolated enum LegacyBackupSourceLineage: String, Codable, Sendable {
    case legacyWebV4 = "legacy-web-v4"
}

nonisolated enum LegacyBackupIssueSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case requiresReview
    case blocking

    fileprivate var sortOrder: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .requiresReview: 2
        case .blocking: 3
        }
    }
}

nonisolated enum LegacyBackupIssueCategory: String, Codable, Sendable {
    case normalization
    case discardedField
    case deprecatedField
    case securityAuthority
    case unsupportedData
    case brokenReference
    case invalidRecord
    case ignoredSocialData
    case photoBinary
    case inlineBinary
    case ambiguousMapping
    case informational
}

nonisolated enum LegacyBackupEntityType: String, Codable, CaseIterable, Sendable {
    case envelope
    case restaurant
    case placeIdentity
    case visit
    case dish
    case visitDish
    case photo
    case companion
    case recommendationSource
    case profile
    case friendship
    case follow
    case sharedMeal
    case sharedMealParticipant
    case restaurantList
    case restaurantListItem
    case tombstone
}

nonisolated enum LegacyBackupIssueCode: String, Codable, Sendable {
    case authorityFieldRemoved
    case deprecatedFieldDiscarded
    case unknownFieldDiscarded
    case unknownTopLevelCollectionDiscarded
    case invalidField
    case invalidRecord
    case duplicateSourceID
    case brokenReference
    case duplicateProviderIdentityRemoved
    case conflictingPrimaryProviderIdentity
    case providerIdentityCollisionAcrossRestaurants
    case providerNeutralRestaurant
    case linkedSocialIdentityRemoved
    case photoProviderLocatorRemoved
    case photoTransientStateRemoved
    case photoBinaryUnavailable
    case inlineBinaryDiscarded
    case serverAuthoritativeSocialDataIgnored
    case legacyFormatDoesNotContainFollows
    case sharedMealReferenceIsNonAuthoritative
    case multipleProfilesRequireReview
    case ambiguousPhotoParent
    case invalidPhotoParent
    case deletedRecordReducedToTombstone
}

nonisolated struct LegacyBackupIssue: Codable, Equatable, Sendable {
    let severity: LegacyBackupIssueSeverity
    let category: LegacyBackupIssueCategory
    let code: LegacyBackupIssueCode
    let entityType: LegacyBackupEntityType
    let sourceRecordID: String?
    let field: String?
    let count: Int
    let approximateByteCount: Int?

    init(
        severity: LegacyBackupIssueSeverity,
        category: LegacyBackupIssueCategory,
        code: LegacyBackupIssueCode,
        entityType: LegacyBackupEntityType,
        sourceRecordID: String? = nil,
        field: String? = nil,
        count: Int = 1,
        approximateByteCount: Int? = nil
    ) {
        self.severity = severity
        self.category = category
        self.code = code
        self.entityType = entityType
        self.sourceRecordID = sourceRecordID
        self.field = field
        self.count = max(1, count)
        self.approximateByteCount = approximateByteCount.map { max(0, $0) }
    }

    fileprivate var stableSortKey: String {
        [
            String(severity.sortOrder),
            category.rawValue,
            code.rawValue,
            entityType.rawValue,
            field ?? "",
            sourceRecordID ?? "",
            String(count),
            String(approximateByteCount ?? -1),
        ].joined(separator: "|")
    }
}

nonisolated struct LegacyBackupSourceCounts: Codable, Equatable, Sendable {
    let restaurants: Int
    let visits: Int
    let embeddedDishes: Int
    let photos: Int
    let users: Int
    let friendships: Int
    let sharedMeals: Int
    let sharedMealParticipants: Int
    let restaurantLists: Int
    let restaurantListItems: Int
}

nonisolated struct LegacyBackupNormalizedCounts: Codable, Equatable, Sendable {
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
}

nonisolated struct LegacyBackupConversionReport: Codable, Equatable, Sendable {
    let sourceLineage: LegacyBackupSourceLineage
    let sourceCounts: LegacyBackupSourceCounts
    let normalizedCounts: LegacyBackupNormalizedCounts
    let issues: [LegacyBackupIssue]

    init(
        sourceCounts: LegacyBackupSourceCounts,
        normalizedCounts: LegacyBackupNormalizedCounts,
        issues: [LegacyBackupIssue]
    ) {
        sourceLineage = .legacyWebV4
        self.sourceCounts = sourceCounts
        self.normalizedCounts = normalizedCounts
        self.issues = issues.sorted { $0.stableSortKey < $1.stableSortKey }
    }

    var discardedFields: [LegacyBackupIssue] {
        issues.filter { $0.category == .discardedField }
    }

    var deprecatedFields: [LegacyBackupIssue] {
        issues.filter { $0.category == .deprecatedField }
    }

    var securityAuthorityFieldsRemoved: [LegacyBackupIssue] {
        issues.filter { $0.category == .securityAuthority }
    }

    var unsupportedData: [LegacyBackupIssue] {
        issues.filter { $0.category == .unsupportedData }
    }

    var brokenReferences: [LegacyBackupIssue] {
        issues.filter { $0.category == .brokenReference }
    }

    var invalidRecords: [LegacyBackupIssue] {
        issues.filter { $0.category == .invalidRecord }
    }

    var ignoredSocialData: [LegacyBackupIssue] {
        issues.filter { $0.category == .ignoredSocialData }
    }

    var photoBinaryIssues: [LegacyBackupIssue] {
        issues.filter { $0.category == .photoBinary || $0.category == .inlineBinary }
    }

    var ambiguousMappings: [LegacyBackupIssue] {
        issues.filter { $0.category == .ambiguousMapping }
    }

    var blockingIssues: [LegacyBackupIssue] {
        issues.filter { $0.severity == .blocking }
    }

    var warnings: [LegacyBackupIssue] {
        issues.filter { $0.severity == .warning }
    }

    var requiresReview: Bool {
        issues.contains { $0.severity == .requiresReview || $0.severity == .blocking }
    }
}
