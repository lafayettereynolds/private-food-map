import CoreFoundation
import CryptoKit
import Foundation

nonisolated struct LegacyWebBackupV4Normalizer {
    func normalize(_ raw: LegacyWebV4RawEnvelope) -> LegacyBackupStagingGraph {
        var state = LegacyNormalizationState(raw: raw)
        state.recordEnvelopeIssues()
        state.convertRestaurants()
        state.convertVisitsAndEmbeddedEntities()
        state.convertProfiles()
        state.convertRestaurantLists()
        state.convertPhotos()
        state.validateReferences()
        return state.makeGraph()
    }
}

private nonisolated struct LegacyNormalizationState {
    let raw: LegacyWebV4RawEnvelope
    var issues = LegacyIssueCollector()
    var restaurants: [LegacyStagingRestaurant] = []
    var visits: [LegacyStagingVisit] = []
    var dishes: [LegacyStagingDish] = []
    var visitDishes: [LegacyStagingVisitDish] = []
    var photos: [LegacyStagingPhoto] = []
    var profiles: [LegacyStagingProfile] = []
    var restaurantLists: [LegacyStagingRestaurantList] = []
    var restaurantListItems: [LegacyStagingRestaurantListItem] = []
    var tombstones: [LegacyStagingTombstone] = []

    var companionAccumulators: [String: LegacyNamedEntityAccumulator] = [:]
    var recommendationSourceAccumulators: [String: LegacyRecommendationSourceAccumulator] = [:]
    var companionIDsByVisit: [String: [String]] = [:]
    var recommendationSourceIDByVisit: [String: String] = [:]
    var visitPhotoReferences: [(visitID: String, photoID: String)] = []
    var dishPhotoReferences: [(dishID: String, photoID: String)] = []

    var seenRestaurantIDs = Set<String>()
    var seenVisitIDs = Set<String>()
    var seenPhotoIDs = Set<String>()
    var seenProfileIDs = Set<String>()
    var seenListIDs = Set<String>()
    var seenListItemIDs = Set<String>()

    init(raw: LegacyWebV4RawEnvelope) {
        self.raw = raw
    }

    mutating func recordEnvelopeIssues() {
        for field in raw.unknownTopLevelFields {
            if LegacyFieldPolicy.isSecurityAuthority(field.name) {
                issues.add(
                    severity: .warning,
                    category: .securityAuthority,
                    code: .authorityFieldRemoved,
                    entityType: .envelope,
                    field: field.name,
                    count: max(1, field.collectionCount ?? 1)
                )
            } else {
                issues.add(
                    severity: field.isCollection ? .requiresReview : .warning,
                    category: .unsupportedData,
                    code: field.isCollection
                        ? .unknownTopLevelCollectionDiscarded
                        : .unknownFieldDiscarded,
                    entityType: .envelope,
                    field: field.name,
                    count: max(1, field.collectionCount ?? 1)
                )
            }
        }

        if !raw.friendships.isEmpty {
            issues.add(
                severity: .warning,
                category: .ignoredSocialData,
                code: .serverAuthoritativeSocialDataIgnored,
                entityType: .friendship,
                count: raw.friendships.count
            )
        }
        if !raw.sharedMeals.isEmpty {
            issues.add(
                severity: .warning,
                category: .ignoredSocialData,
                code: .serverAuthoritativeSocialDataIgnored,
                entityType: .sharedMeal,
                count: raw.sharedMeals.count
            )
        }
        if !raw.sharedMealParticipants.isEmpty {
            issues.add(
                severity: .warning,
                category: .ignoredSocialData,
                code: .serverAuthoritativeSocialDataIgnored,
                entityType: .sharedMealParticipant,
                count: raw.sharedMealParticipants.count
            )
        }
        issues.add(
            severity: .info,
            category: .informational,
            code: .legacyFormatDoesNotContainFollows,
            entityType: .follow
        )
    }

    mutating func makeGraph() -> LegacyBackupStagingGraph {
        let companions = companionAccumulators.values.map { accumulator in
            LegacyStagingDiningCompanion(
                sourceLineage: .legacyWebV4,
                sourceID: accumulator.sourceID,
                displayName: accumulator.displayName,
                firstObservedAt: accumulator.firstObservedAt,
                lastObservedAt: accumulator.lastObservedAt
            )
        }.sorted { $0.sourceID < $1.sourceID }

        let recommendationSources = recommendationSourceAccumulators.values.map { accumulator in
            LegacyStagingRecommendationSource(
                sourceLineage: .legacyWebV4,
                sourceID: accumulator.sourceID,
                displayName: accumulator.displayName,
                sourceType: accumulator.sourceType,
                firstObservedAt: accumulator.firstObservedAt,
                lastObservedAt: accumulator.lastObservedAt
            )
        }.sorted { $0.sourceID < $1.sourceID }

        restaurants.sort { $0.sourceID < $1.sourceID }
        visits.sort { $0.sourceID < $1.sourceID }
        dishes.sort { $0.sourceID < $1.sourceID }
        visitDishes.sort { $0.sourceID < $1.sourceID }
        photos.sort { $0.sourceID < $1.sourceID }
        profiles.sort { $0.sourceID < $1.sourceID }
        restaurantLists.sort { $0.sourceID < $1.sourceID }
        restaurantListItems.sort {
            if $0.sourceListID != $1.sourceListID { return $0.sourceListID < $1.sourceListID }
            if ($0.position ?? .max) != ($1.position ?? .max) {
                return ($0.position ?? .max) < ($1.position ?? .max)
            }
            return $0.sourceID < $1.sourceID
        }
        tombstones.sort {
            if $0.entityType.rawValue != $1.entityType.rawValue {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            return $0.sourceID < $1.sourceID
        }

        visits = visits.map { visit in
            LegacyStagingVisit(
                sourceLineage: visit.sourceLineage,
                sourceID: visit.sourceID,
                sourceRestaurantID: visit.sourceRestaurantID,
                visitedAt: visit.visitedAt,
                diningMode: visit.diningMode,
                visibility: visit.visibility,
                totalPrice: visit.totalPrice,
                myActualSpend: visit.myActualSpend,
                paymentMode: visit.paymentMode,
                pricePerPerson: visit.pricePerPerson,
                partySize: visit.partySize,
                queueDuration: visit.queueDuration,
                diningOccasions: visit.diningOccasions,
                diningOccasionText: visit.diningOccasionText,
                rating: visit.rating,
                valueRating: visit.valueRating,
                environmentRating: visit.environmentRating,
                serviceRating: visit.serviceRating,
                valueTags: visit.valueTags,
                environmentTags: visit.environmentTags,
                serviceTags: visit.serviceTags,
                noiseLevel: visit.noiseLevel,
                diningDuration: visit.diningDuration,
                portionLevel: visit.portionLevel,
                transportConvenience: visit.transportConvenience,
                specialNotes: visit.specialNotes,
                recommendationSourceID: recommendationSourceIDByVisit[visit.sourceID],
                recommendationSourceType: visit.recommendationSourceType,
                recommendationSourceText: visit.recommendationSourceText,
                sharedMealReferenceHint: visit.sharedMealReferenceHint,
                companionSourceIDs: companionIDsByVisit[visit.sourceID] ?? [],
                note: visit.note,
                createdAt: visit.createdAt,
                updatedAt: visit.updatedAt
            )
        }

        let sourceCounts = LegacyBackupSourceCounts(
            restaurants: raw.restaurants.count,
            visits: raw.visits.count,
            embeddedDishes: raw.visits.reduce(0) { partial, record in
                partial + ((record.object?["dishes"] as? [Any])?.count ?? 0)
            },
            photos: raw.photos.count,
            users: raw.users.count,
            friendships: raw.friendships.count,
            sharedMeals: raw.sharedMeals.count,
            sharedMealParticipants: raw.sharedMealParticipants.count,
            restaurantLists: raw.restaurantLists.count,
            restaurantListItems: raw.restaurantListItems.count
        )
        let normalizedCounts = LegacyBackupNormalizedCounts(
            restaurants: restaurants.count,
            visits: visits.count,
            dishes: dishes.count,
            visitDishes: visitDishes.count,
            photos: photos.count,
            companions: companions.count,
            recommendationSources: recommendationSources.count,
            profiles: profiles.count,
            restaurantLists: restaurantLists.count,
            restaurantListItems: restaurantListItems.count,
            tombstones: tombstones.count
        )
        let report = LegacyBackupConversionReport(
            sourceCounts: sourceCounts,
            normalizedCounts: normalizedCounts,
            issues: issues.materialized
        )
        return LegacyBackupStagingGraph(
            sourceMetadata: raw.sourceMetadata,
            restaurants: restaurants,
            visits: visits,
            dishes: dishes,
            visitDishes: visitDishes,
            photos: photos,
            companions: companions,
            recommendationSources: recommendationSources,
            profiles: profiles,
            restaurantLists: restaurantLists,
            restaurantListItems: restaurantListItems,
            tombstones: tombstones,
            conversionReport: report
        )
    }
}

private nonisolated struct LegacyNamedEntityAccumulator {
    let sourceID: String
    let displayName: String
    var firstObservedAt: BackupTimestampV1?
    var lastObservedAt: BackupTimestampV1?

    mutating func observe(_ timestamp: BackupTimestampV1?) {
        guard let timestamp else { return }
        if firstObservedAt == nil || timestamp.rawValue < firstObservedAt!.rawValue {
            firstObservedAt = timestamp
        }
        if lastObservedAt == nil || timestamp.rawValue > lastObservedAt!.rawValue {
            lastObservedAt = timestamp
        }
    }
}

private nonisolated struct LegacyRecommendationSourceAccumulator {
    let sourceID: String
    let displayName: String
    let sourceType: BackupRecommendationSourceTypeV1?
    var firstObservedAt: BackupTimestampV1?
    var lastObservedAt: BackupTimestampV1?

    mutating func observe(_ timestamp: BackupTimestampV1?) {
        guard let timestamp else { return }
        if firstObservedAt == nil || timestamp.rawValue < firstObservedAt!.rawValue {
            firstObservedAt = timestamp
        }
        if lastObservedAt == nil || timestamp.rawValue > lastObservedAt!.rawValue {
            lastObservedAt = timestamp
        }
    }
}

private nonisolated struct LegacyIssueCollector {
    private struct Aggregate {
        var issue: LegacyBackupIssue
        var count: Int
        var approximateByteCount: Int?
    }

    private var aggregates: [String: Aggregate] = [:]

    mutating func add(
        severity: LegacyBackupIssueSeverity,
        category: LegacyBackupIssueCategory,
        code: LegacyBackupIssueCode,
        entityType: LegacyBackupEntityType,
        sourceRecordID: String? = nil,
        field: String? = nil,
        count: Int = 1,
        approximateByteCount: Int? = nil
    ) {
        let key = [
            severity.rawValue, category.rawValue, code.rawValue, entityType.rawValue,
            sourceRecordID ?? "", field ?? "",
        ].joined(separator: "|")
        if var aggregate = aggregates[key] {
            aggregate.count += max(1, count)
            if let approximateByteCount {
                aggregate.approximateByteCount = (aggregate.approximateByteCount ?? 0)
                    + max(0, approximateByteCount)
            }
            aggregates[key] = aggregate
        } else {
            let issue = LegacyBackupIssue(
                severity: severity,
                category: category,
                code: code,
                entityType: entityType,
                sourceRecordID: sourceRecordID,
                field: field,
                count: max(1, count),
                approximateByteCount: approximateByteCount
            )
            aggregates[key] = Aggregate(
                issue: issue,
                count: max(1, count),
                approximateByteCount: approximateByteCount
            )
        }
    }

    var materialized: [LegacyBackupIssue] {
        aggregates.values.map { aggregate in
            LegacyBackupIssue(
                severity: aggregate.issue.severity,
                category: aggregate.issue.category,
                code: aggregate.issue.code,
                entityType: aggregate.issue.entityType,
                sourceRecordID: aggregate.issue.sourceRecordID,
                field: aggregate.issue.field,
                count: aggregate.count,
                approximateByteCount: aggregate.approximateByteCount
            )
        }
    }
}

private nonisolated enum LegacyFieldPolicy {
    private static let authorityTokens = [
        "userid", "ownerid", "owneruserid", "authsubject", "authprovider", "applesub",
        "email", "membership", "premium", "entitlement", "admin", "role",
        "accesstoken", "refreshtoken", "identitytoken", "oauth", "secret",
        "credential", "session", "nonce", "serverversion", "synccursor",
        "syncmutation", "mutationreceipt", "remoterecorddata", "localpath",
        "temporarypath", "cachepath", "provideraccountid",
    ]

    static func isSecurityAuthority(_ field: String) -> Bool {
        let normalized = field.lowercased().filter(\.isLetter)
        return authorityTokens.contains { normalized.contains($0) }
    }
}

private nonisolated enum LegacyRecordParsing {
    static func inspectFields(
        _ object: [String: Any],
        allowed: Set<String>,
        deprecated: Set<String> = [],
        specializedDiscarded: Set<String> = [],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        issues: inout LegacyIssueCollector
    ) {
        for field in object.keys.sorted() {
            if deprecated.contains(field) {
                issues.add(
                    severity: .warning,
                    category: .deprecatedField,
                    code: .deprecatedFieldDiscarded,
                    entityType: entityType,
                    field: field
                )
            } else if specializedDiscarded.contains(field) || allowed.contains(field) {
                continue
            } else if LegacyFieldPolicy.isSecurityAuthority(field) {
                issues.add(
                    severity: .warning,
                    category: .securityAuthority,
                    code: .authorityFieldRemoved,
                    entityType: entityType,
                    field: field
                )
            } else {
                issues.add(
                    severity: .warning,
                    category: .unsupportedData,
                    code: .unknownFieldDiscarded,
                    entityType: entityType,
                    field: field
                )
            }
        }
    }

    static func requiredID(
        _ object: [String: Any],
        entityType: LegacyBackupEntityType,
        issues: inout LegacyIssueCollector
    ) -> String? {
        guard let raw = object["id"] as? String else {
            issues.add(
                severity: .blocking,
                category: .invalidRecord,
                code: .invalidRecord,
                entityType: entityType,
                field: "id"
            )
            return nil
        }
        let value = LegacyValueNormalization.normalizedName(raw)
        guard !value.isEmpty, value.utf8.count <= 512 else {
            issues.add(
                severity: .blocking,
                category: .invalidRecord,
                code: .invalidRecord,
                entityType: entityType,
                field: "id"
            )
            return nil
        }
        return value
    }

    static func string(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        maxUTF8: Int,
        required: Bool = false,
        trim: Bool = false,
        allowEmpty: Bool = true,
        issues: inout LegacyIssueCollector
    ) -> String? {
        guard let rawValue = object[field], !(rawValue is NSNull) else {
            if required {
                issues.add(
                    severity: .blocking,
                    category: .invalidRecord,
                    code: .invalidField,
                    entityType: entityType,
                    sourceRecordID: sourceID,
                    field: field
                )
            }
            return nil
        }
        guard let raw = rawValue as? String else {
            issues.add(
                severity: required ? .blocking : .warning,
                category: .invalidRecord,
                code: .invalidField,
                entityType: entityType,
                sourceRecordID: sourceID,
                field: field
            )
            return nil
        }
        let normalized = raw.precomposedStringWithCanonicalMapping
        let value = trim ? normalized.trimmingCharacters(in: .whitespacesAndNewlines) : normalized
        guard value.utf8.count <= maxUTF8, allowEmpty || !value.isEmpty else {
            issues.add(
                severity: required ? .blocking : .warning,
                category: .invalidRecord,
                code: .invalidField,
                entityType: entityType,
                sourceRecordID: sourceID,
                field: field
            )
            return nil
        }
        return value
    }

    static func bool(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        issues: inout LegacyIssueCollector
    ) -> Bool? {
        guard let raw = object[field], !(raw is NSNull) else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        return number.boolValue
    }

    static func double(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        required: Bool = false,
        range: ClosedRange<Double>? = nil,
        issues: inout LegacyIssueCollector
    ) -> Double? {
        guard let raw = object[field], !(raw is NSNull) else {
            if required { invalid(field, severity: .blocking, entityType: entityType, sourceID: sourceID, issues: &issues) }
            return nil
        }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else {
            invalid(field, severity: required ? .blocking : .warning, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        let value = number.doubleValue
        if let range, !range.contains(value) {
            invalid(field, severity: required ? .blocking : .warning, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        return value
    }

    static func integer(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        minimum: Int? = nil,
        issues: inout LegacyIssueCollector
    ) -> Int? {
        guard let raw = object[field], !(raw is NSNull) else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        let value = Int(double)
        if let minimum, value < minimum {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        return value
    }

    static func timestamp(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        issues: inout LegacyIssueCollector
    ) -> BackupTimestampV1? {
        guard let raw = object[field], !(raw is NSNull) else { return nil }
        guard let source = raw as? String,
              let timestamp = LegacyValueNormalization.timestamp(source) else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        return timestamp
    }

    static func rating(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        issues: inout LegacyIssueCollector
    ) -> BackupRatingV1? {
        guard let raw = object[field], !(raw is NSNull) else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let rating = BackupRatingV1(rawValue: number.doubleValue) else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        return rating
    }

    static func money(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        issues: inout LegacyIssueCollector
    ) -> BackupMoneyV1? {
        guard let raw = object[field], !(raw is NSNull) else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue >= 0, number.doubleValue < 10_000_000_000_000_000 else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        var source = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        if rounded != source {
            issues.add(
                severity: .requiresReview,
                category: .normalization,
                code: .invalidField,
                entityType: entityType,
                sourceRecordID: sourceID,
                field: field
            )
        }
        var string = NSDecimalNumber(decimal: rounded).stringValue
        if let dot = string.firstIndex(of: ".") {
            let decimals = string.distance(from: string.index(after: dot), to: string.endIndex)
            if decimals == 0 { string += "00" }
            if decimals == 1 { string += "0" }
        } else {
            string += ".00"
        }
        guard let money = BackupMoneyV1(rawValue: string) else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        return money
    }

    static func enumValue<Value: RawRepresentable>(
        _ type: Value.Type,
        field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        required: Bool = false,
        issues: inout LegacyIssueCollector
    ) -> Value? where Value.RawValue == String {
        guard let raw = object[field], !(raw is NSNull) else {
            if required { invalid(field, severity: .warning, entityType: entityType, sourceID: sourceID, issues: &issues) }
            return nil
        }
        guard let string = raw as? String, let value = Value(rawValue: string) else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        return value
    }

    static func stringArray(
        _ field: String,
        from object: [String: Any],
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        maxItemUTF8: Int,
        trim: Bool = false,
        issues: inout LegacyIssueCollector
    ) -> [String]? {
        guard let raw = object[field], !(raw is NSNull) else { return nil }
        guard let array = raw as? [Any] else {
            invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
            return nil
        }
        var result: [String] = []
        for value in array {
            guard let source = value as? String else {
                invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
                continue
            }
            let normalized = source.precomposedStringWithCanonicalMapping
            let candidate = trim
                ? normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                : normalized
            guard candidate.utf8.count <= maxItemUTF8 else {
                invalid(field, entityType: entityType, sourceID: sourceID, issues: &issues)
                continue
            }
            result.append(candidate)
        }
        return result
    }

    static func inlineApproximateBytes(_ value: Any?) -> Int? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        let payload = string.split(separator: ",", maxSplits: 1).last.map(String.init) ?? string
        return max(0, payload.utf8.count * 3 / 4)
    }

    static func invalid(
        _ field: String,
        severity: LegacyBackupIssueSeverity = .warning,
        entityType: LegacyBackupEntityType,
        sourceID: String?,
        issues: inout LegacyIssueCollector
    ) {
        issues.add(
            severity: severity,
            category: .invalidRecord,
            code: .invalidField,
            entityType: entityType,
            sourceRecordID: sourceID,
            field: field
        )
    }

    static func stableHashedSourceID(namespace: String, key: String) -> String {
        let digest = SHA256.hash(data: Data("legacy-web-v4|\(namespace)|\(key)".utf8))
        return "legacy-\(namespace)-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

private nonisolated extension LegacyNormalizationState {
    static let restaurantFields: Set<String> = [
        "id", "amapPoiId", "placeIdentities", "name", "address", "city",
        "latitude", "longitude", "status", "preferenceLevel", "overallRating",
        "foodRating", "environmentRating", "serviceRating", "valueRating", "tags",
        "longTermNote", "pricePerPerson", "phone", "openingHours", "markerType",
        "markerImageData", "markerPhotoId", "merchantImageUrl", "markerEmoji",
        "createdAt", "updatedAt", "deletedAt",
    ]

    mutating func convertRestaurants() {
        for record in raw.restaurants {
            guard let object = record.object else {
                issues.add(
                    severity: .blocking,
                    category: .invalidRecord,
                    code: .invalidRecord,
                    entityType: .restaurant,
                    count: 1
                )
                continue
            }
            let sourceID = LegacyRecordParsing.requiredID(
                object,
                entityType: .restaurant,
                issues: &issues
            )
            LegacyRecordParsing.inspectFields(
                object,
                allowed: Self.restaurantFields,
                specializedDiscarded: ["markerImageData"],
                entityType: .restaurant,
                sourceID: sourceID,
                issues: &issues
            )
            guard let sourceID else { continue }
            guard seenRestaurantIDs.insert(sourceID).inserted else {
                duplicateID(sourceID, entityType: .restaurant)
                continue
            }
            if let inlineBytes = LegacyRecordParsing.inlineApproximateBytes(object["markerImageData"]) {
                issues.add(
                    severity: .warning,
                    category: .inlineBinary,
                    code: .inlineBinaryDiscarded,
                    entityType: .restaurant,
                    sourceRecordID: sourceID,
                    field: "markerImageData",
                    approximateByteCount: inlineBytes
                )
            }
            if let deletedAt = tombstoneTimestamp(
                object,
                field: "deletedAt",
                entityType: .restaurant,
                sourceID: sourceID
            ) {
                tombstones.append(.init(
                    sourceLineage: .legacyWebV4,
                    entityType: .restaurant,
                    sourceID: sourceID,
                    deletedAt: deletedAt
                ))
                recordTombstoneReduction(entityType: .restaurant, sourceID: sourceID)
                continue
            } else if hasNonNullValue("deletedAt", in: object) {
                continue
            }

            guard let name = LegacyRecordParsing.string(
                "name",
                from: object,
                entityType: .restaurant,
                sourceID: sourceID,
                maxUTF8: 500,
                required: true,
                trim: true,
                allowEmpty: false,
                issues: &issues
            ), let latitude = LegacyRecordParsing.double(
                "latitude",
                from: object,
                entityType: .restaurant,
                sourceID: sourceID,
                required: true,
                range: -90 ... 90,
                issues: &issues
            ), let longitude = LegacyRecordParsing.double(
                "longitude",
                from: object,
                entityType: .restaurant,
                sourceID: sourceID,
                required: true,
                range: -180 ... 180,
                issues: &issues
            ) else {
                continue
            }

            let identities = convertPlaceIdentities(object, restaurantID: sourceID)
            if identities.isEmpty {
                issues.add(
                    severity: .info,
                    category: .normalization,
                    code: .providerNeutralRestaurant,
                    entityType: .restaurant,
                    sourceRecordID: sourceID,
                    field: "placeIdentities"
                )
            }
            restaurants.append(.init(
                sourceLineage: .legacyWebV4,
                sourceID: sourceID,
                placeIdentities: identities,
                name: name,
                address: LegacyRecordParsing.string(
                    "address", from: object, entityType: .restaurant, sourceID: sourceID,
                    maxUTF8: 2_000, issues: &issues
                ),
                city: LegacyRecordParsing.string(
                    "city", from: object, entityType: .restaurant, sourceID: sourceID,
                    maxUTF8: 500, issues: &issues
                ),
                latitude: latitude,
                longitude: longitude,
                status: LegacyRecordParsing.enumValue(
                    BackupRestaurantStatusV1.self, field: "status", from: object,
                    entityType: .restaurant, sourceID: sourceID, required: true, issues: &issues
                ),
                preferenceLevel: LegacyRecordParsing.enumValue(
                    BackupRestaurantPreferenceV1.self, field: "preferenceLevel", from: object,
                    entityType: .restaurant, sourceID: sourceID, required: true, issues: &issues
                ),
                overallRating: LegacyRecordParsing.rating(
                    "overallRating", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                ),
                foodRating: LegacyRecordParsing.rating(
                    "foodRating", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                ),
                environmentRating: LegacyRecordParsing.rating(
                    "environmentRating", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                ),
                serviceRating: LegacyRecordParsing.rating(
                    "serviceRating", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                ),
                valueRating: LegacyRecordParsing.rating(
                    "valueRating", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                ),
                tags: LegacyRecordParsing.stringArray(
                    "tags", from: object, entityType: .restaurant, sourceID: sourceID,
                    maxItemUTF8: 200, issues: &issues
                ),
                longTermNote: LegacyRecordParsing.string(
                    "longTermNote", from: object, entityType: .restaurant, sourceID: sourceID,
                    maxUTF8: 20_000, issues: &issues
                ),
                pricePerPerson: LegacyRecordParsing.money(
                    "pricePerPerson", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                ),
                phone: LegacyRecordParsing.string(
                    "phone", from: object, entityType: .restaurant, sourceID: sourceID,
                    maxUTF8: 200, issues: &issues
                ),
                openingHours: LegacyRecordParsing.string(
                    "openingHours", from: object, entityType: .restaurant, sourceID: sourceID,
                    maxUTF8: 2_000, issues: &issues
                ),
                markerType: LegacyRecordParsing.enumValue(
                    BackupMarkerTypeV1.self, field: "markerType", from: object,
                    entityType: .restaurant, sourceID: sourceID, issues: &issues
                ),
                markerPhotoSourceID: LegacyRecordParsing.string(
                    "markerPhotoId", from: object, entityType: .restaurant, sourceID: sourceID,
                    maxUTF8: 512, trim: true, allowEmpty: false, issues: &issues
                ),
                merchantImageURL: LegacyRecordParsing.string(
                    "merchantImageUrl", from: object, entityType: .restaurant,
                    sourceID: sourceID, maxUTF8: 4_096, issues: &issues
                ),
                markerEmoji: LegacyRecordParsing.string(
                    "markerEmoji", from: object, entityType: .restaurant,
                    sourceID: sourceID, maxUTF8: 100, issues: &issues
                ),
                createdAt: LegacyRecordParsing.timestamp(
                    "createdAt", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                ),
                updatedAt: LegacyRecordParsing.timestamp(
                    "updatedAt", from: object, entityType: .restaurant,
                    sourceID: sourceID, issues: &issues
                )
            ))
        }
        validateGlobalPlaceIdentityUniqueness()
    }

    mutating func convertPlaceIdentities(
        _ object: [String: Any],
        restaurantID: String
    ) -> [LegacyStagingPlaceIdentity] {
        var identities: [LegacyStagingPlaceIdentity] = []
        var seen = Set<String>()
        if let rawIdentities = object["placeIdentities"], !(rawIdentities is NSNull) {
            if let array = rawIdentities as? [Any] {
                for value in array {
                    guard let identity = value as? [String: Any] else {
                        issues.add(
                            severity: .warning,
                            category: .invalidRecord,
                            code: .invalidRecord,
                            entityType: .placeIdentity,
                            sourceRecordID: restaurantID
                        )
                        continue
                    }
                    LegacyRecordParsing.inspectFields(
                        identity,
                        allowed: ["provider", "externalId", "isPrimary", "createdAt", "updatedAt"],
                        entityType: .placeIdentity,
                        sourceID: restaurantID,
                        issues: &issues
                    )
                    guard let provider = LegacyRecordParsing.enumValue(
                        BackupPlaceProviderV1.self,
                        field: "provider",
                        from: identity,
                        entityType: .placeIdentity,
                        sourceID: restaurantID,
                        required: true,
                        issues: &issues
                    ), let externalID = LegacyRecordParsing.string(
                        "externalId", from: identity, entityType: .placeIdentity,
                        sourceID: restaurantID, maxUTF8: 512, required: true,
                        trim: true, allowEmpty: false, issues: &issues
                    ), let isPrimary = LegacyRecordParsing.bool(
                        "isPrimary", from: identity, entityType: .placeIdentity,
                        sourceID: restaurantID, issues: &issues
                    ) else {
                        continue
                    }
                    let key = "\(provider.rawValue)|\(externalID)"
                    guard seen.insert(key).inserted else {
                        issues.add(
                            severity: .warning,
                            category: .normalization,
                            code: .duplicateProviderIdentityRemoved,
                            entityType: .placeIdentity,
                            sourceRecordID: restaurantID,
                            field: "placeIdentities"
                        )
                        continue
                    }
                    identities.append(.init(
                        sourceLineage: .legacyWebV4,
                        provider: provider,
                        externalID: externalID,
                        isPrimary: isPrimary,
                        createdAt: LegacyRecordParsing.timestamp(
                            "createdAt", from: identity, entityType: .placeIdentity,
                            sourceID: restaurantID, issues: &issues
                        ),
                        updatedAt: LegacyRecordParsing.timestamp(
                            "updatedAt", from: identity, entityType: .placeIdentity,
                            sourceID: restaurantID, issues: &issues
                        )
                    ))
                }
            } else {
                LegacyRecordParsing.invalid(
                    "placeIdentities", entityType: .restaurant,
                    sourceID: restaurantID, issues: &issues
                )
            }
        }

        if let amapPoiID = LegacyRecordParsing.string(
            "amapPoiId", from: object, entityType: .restaurant,
            sourceID: restaurantID, maxUTF8: 512, trim: true,
            issues: &issues
        ), !amapPoiID.isEmpty {
            let key = "\(BackupPlaceProviderV1.amap.rawValue)|\(amapPoiID)"
            if seen.insert(key).inserted {
                identities.append(.init(
                    sourceLineage: .legacyWebV4,
                    provider: .amap,
                    externalID: amapPoiID,
                    isPrimary: identities.isEmpty,
                    createdAt: LegacyRecordParsing.timestamp(
                        "createdAt", from: object, entityType: .restaurant,
                        sourceID: restaurantID, issues: &issues
                    ),
                    updatedAt: LegacyRecordParsing.timestamp(
                        "updatedAt", from: object, entityType: .restaurant,
                        sourceID: restaurantID, issues: &issues
                    )
                ))
            }
        }

        if identities.filter(\.isPrimary).count > 1 {
            issues.add(
                severity: .requiresReview,
                category: .ambiguousMapping,
                code: .conflictingPrimaryProviderIdentity,
                entityType: .restaurant,
                sourceRecordID: restaurantID,
                field: "placeIdentities"
            )
        }
        return identities.sorted {
            if $0.provider.rawValue != $1.provider.rawValue {
                return $0.provider.rawValue < $1.provider.rawValue
            }
            return $0.externalID < $1.externalID
        }
    }

    mutating func validateGlobalPlaceIdentityUniqueness() {
        var ownerByIdentity: [String: String] = [:]
        for restaurant in restaurants.sorted(by: { $0.sourceID < $1.sourceID }) {
            for identity in restaurant.placeIdentities {
                let key = "\(identity.provider.rawValue)|\(identity.externalID)"
                if let existing = ownerByIdentity[key], existing != restaurant.sourceID {
                    issues.add(
                        severity: .requiresReview,
                        category: .ambiguousMapping,
                        code: .providerIdentityCollisionAcrossRestaurants,
                        entityType: .restaurant,
                        sourceRecordID: restaurant.sourceID,
                        field: "placeIdentities"
                    )
                } else {
                    ownerByIdentity[key] = restaurant.sourceID
                }
            }
        }
    }
}

private nonisolated extension LegacyNormalizationState {
    static let photoFields: Set<String> = [
        "id", "restaurantId", "visitId", "kind", "fileName", "mimeType", "fileSize",
        "width", "height", "visibility", "createdAt", "updatedAt", "deletedAt",
    ]
    static let photoProviderFields: Set<String> = [
        "storageProvider", "storageKey", "thumbnailStorageKey", "driveAccountId", "driveFileId",
    ]
    static let photoTransientFields: Set<String> = [
        "syncStatus", "localState", "lastError",
    ]
    static let photoUnsupportedFields: Set<String> = ["thumbnailFileSize"]

    mutating func convertPhotos() {
        let dishIDsByPhotoID = Dictionary(grouping: dishPhotoReferences, by: \.photoID)
            .mapValues { $0.map(\.dishID).sorted() }
        let profileIDsByPhotoID = Dictionary(
            grouping: profiles.compactMap { profile -> (photoID: String, profileID: String)? in
                guard let photoID = profile.avatarPhotoSourceID else { return nil }
                return (photoID: photoID, profileID: profile.sourceID)
            },
            by: \.photoID
        ).mapValues { $0.map(\.profileID).sorted() }

        for record in raw.photos {
            guard let object = record.object else {
                issues.add(
                    severity: .blocking,
                    category: .invalidRecord,
                    code: .invalidRecord,
                    entityType: .photo
                )
                continue
            }
            let sourceID = LegacyRecordParsing.requiredID(
                object, entityType: .photo, issues: &issues
            )
            LegacyRecordParsing.inspectFields(
                object,
                allowed: Self.photoFields,
                specializedDiscarded: Self.photoProviderFields
                    .union(Self.photoTransientFields)
                    .union(Self.photoUnsupportedFields),
                entityType: .photo,
                sourceID: sourceID,
                issues: &issues
            )
            for field in Self.photoProviderFields.sorted() where hasNonNullValue(field, in: object) {
                issues.add(
                    severity: .warning,
                    category: .discardedField,
                    code: .photoProviderLocatorRemoved,
                    entityType: .photo,
                    field: field
                )
            }
            for field in Self.photoTransientFields.sorted() where hasNonNullValue(field, in: object) {
                issues.add(
                    severity: .info,
                    category: .discardedField,
                    code: .photoTransientStateRemoved,
                    entityType: .photo,
                    field: field
                )
            }
            for field in Self.photoUnsupportedFields.sorted() where hasNonNullValue(field, in: object) {
                issues.add(
                    severity: .info,
                    category: .discardedField,
                    code: .unknownFieldDiscarded,
                    entityType: .photo,
                    field: field
                )
            }
            guard let sourceID else { continue }
            guard seenPhotoIDs.insert(sourceID).inserted else {
                duplicateID(sourceID, entityType: .photo)
                continue
            }
            if let deletedAt = tombstoneTimestamp(
                object, field: "deletedAt", entityType: .photo, sourceID: sourceID
            ) {
                tombstones.append(.init(
                    sourceLineage: .legacyWebV4,
                    entityType: .photo,
                    sourceID: sourceID,
                    deletedAt: deletedAt
                ))
                recordTombstoneReduction(entityType: .photo, sourceID: sourceID)
                continue
            } else if hasNonNullValue("deletedAt", in: object) {
                continue
            }
            guard let kind = LegacyRecordParsing.enumValue(
                BackupPhotoKindV1.self,
                field: "kind",
                from: object,
                entityType: .photo,
                sourceID: sourceID,
                required: true,
                issues: &issues
            ), let parent = photoParent(
                kind: kind,
                photoID: sourceID,
                object: object,
                dishIDsByPhotoID: dishIDsByPhotoID,
                profileIDsByPhotoID: profileIDsByPhotoID
            ) else {
                continue
            }
            photos.append(.init(
                sourceLineage: .legacyWebV4,
                sourceID: sourceID,
                kind: kind,
                parent: parent,
                fileName: LegacyRecordParsing.string(
                    "fileName", from: object, entityType: .photo, sourceID: sourceID,
                    maxUTF8: 1_000, issues: &issues
                ),
                mimeType: LegacyRecordParsing.string(
                    "mimeType", from: object, entityType: .photo, sourceID: sourceID,
                    maxUTF8: 200, issues: &issues
                ),
                byteSize: LegacyRecordParsing.integer(
                    "fileSize", from: object, entityType: .photo,
                    sourceID: sourceID, minimum: 0, issues: &issues
                ),
                width: LegacyRecordParsing.integer(
                    "width", from: object, entityType: .photo,
                    sourceID: sourceID, minimum: 1, issues: &issues
                ),
                height: LegacyRecordParsing.integer(
                    "height", from: object, entityType: .photo,
                    sourceID: sourceID, minimum: 1, issues: &issues
                ),
                sourceOrder: record.sourceIndex,
                visibility: LegacyRecordParsing.enumValue(
                    BackupVisibilityV1.self, field: "visibility", from: object,
                    entityType: .photo, sourceID: sourceID, issues: &issues
                ),
                createdAt: LegacyRecordParsing.timestamp(
                    "createdAt", from: object, entityType: .photo,
                    sourceID: sourceID, issues: &issues
                ),
                updatedAt: LegacyRecordParsing.timestamp(
                    "updatedAt", from: object, entityType: .photo,
                    sourceID: sourceID, issues: &issues
                ),
                binaryAvailable: false
            ))
            issues.add(
                severity: .warning,
                category: .photoBinary,
                code: .photoBinaryUnavailable,
                entityType: .photo
            )
        }
    }

    mutating func photoParent(
        kind: BackupPhotoKindV1,
        photoID: String,
        object: [String: Any],
        dishIDsByPhotoID: [String: [String]],
        profileIDsByPhotoID: [String: [String]]
    ) -> LegacyStagingPhotoParent? {
        let restaurantID = LegacyRecordParsing.string(
            "restaurantId", from: object, entityType: .photo, sourceID: photoID,
            maxUTF8: 512, trim: true, allowEmpty: false, issues: &issues
        )
        let visitID = LegacyRecordParsing.string(
            "visitId", from: object, entityType: .photo, sourceID: photoID,
            maxUTF8: 512, trim: true, allowEmpty: false, issues: &issues
        )
        let candidates: [LegacyStagingPhotoParent]
        switch kind {
        case .restaurantMarker:
            candidates = restaurantID.map {
                [.init(entityType: .restaurant, sourceID: $0)]
            } ?? []
        case .visit:
            candidates = visitID.map {
                [.init(entityType: .visit, sourceID: $0)]
            } ?? []
        case .dish:
            candidates = (dishIDsByPhotoID[photoID] ?? []).map {
                .init(entityType: .dish, sourceID: $0)
            }
        case .avatar:
            candidates = (profileIDsByPhotoID[photoID] ?? []).map {
                .init(entityType: .profile, sourceID: $0)
            }
        }
        if candidates.count > 1 {
            issues.add(
                severity: .requiresReview,
                category: .ambiguousMapping,
                code: .ambiguousPhotoParent,
                entityType: .photo,
                sourceRecordID: photoID,
                field: "parent"
            )
            return nil
        }
        guard let parent = candidates.first else {
            issues.add(
                severity: .blocking,
                category: .brokenReference,
                code: .invalidPhotoParent,
                entityType: .photo,
                sourceRecordID: photoID,
                field: "parent"
            )
            return nil
        }
        return parent
    }
}

private nonisolated extension LegacyNormalizationState {
    mutating func validateReferences() {
        let restaurantIDs = Set(restaurants.map(\.sourceID))
        let visitIDs = Set(visits.map(\.sourceID))
        let dishIDs = Set(dishes.map(\.sourceID))
        let visitDishIDs = Set(visitDishes.map(\.sourceID))
        let photoIDs = Set(photos.map(\.sourceID))
        let profileIDs = Set(profiles.map(\.sourceID))
        let listIDs = Set(restaurantLists.map(\.sourceID))

        for visit in visits where !restaurantIDs.contains(visit.sourceRestaurantID) {
            brokenReference(.visit, sourceID: visit.sourceID, field: "restaurantId")
        }
        for dish in dishes {
            if !restaurantIDs.contains(dish.sourceRestaurantID) {
                brokenReference(.dish, sourceID: dish.sourceID, field: "restaurantId")
            }
            if !visitIDs.contains(dish.sourceVisitID) {
                brokenReference(.dish, sourceID: dish.sourceID, field: "visitId")
            }
        }
        for association in visitDishes {
            if !visitIDs.contains(association.sourceVisitID) {
                brokenReference(.visitDish, sourceID: association.sourceID, field: "visitId")
            }
            if !restaurantIDs.contains(association.sourceRestaurantID) {
                brokenReference(.visitDish, sourceID: association.sourceID, field: "restaurantId")
            }
            if !dishIDs.contains(association.sourceDishID) {
                brokenReference(.visitDish, sourceID: association.sourceID, field: "dishId")
            }
        }
        #if DEBUG
        assert(visitDishIDs.count == visitDishes.count)
        #endif
        for photo in photos {
            let exists: Bool
            switch photo.parent.entityType {
            case .restaurant: exists = restaurantIDs.contains(photo.parent.sourceID)
            case .visit: exists = visitIDs.contains(photo.parent.sourceID)
            case .dish: exists = dishIDs.contains(photo.parent.sourceID)
            case .profile: exists = profileIDs.contains(photo.parent.sourceID)
            }
            if !exists {
                brokenReference(.photo, sourceID: photo.sourceID, field: "parent")
            }
        }
        for restaurant in restaurants {
            if let photoID = restaurant.markerPhotoSourceID, !photoIDs.contains(photoID) {
                brokenReference(.restaurant, sourceID: restaurant.sourceID, field: "markerPhotoId")
            }
        }
        for reference in visitPhotoReferences where !photoIDs.contains(reference.photoID) {
            brokenReference(.visit, sourceID: reference.visitID, field: "photoIds")
        }
        for reference in dishPhotoReferences where !photoIDs.contains(reference.photoID) {
            brokenReference(.dish, sourceID: reference.dishID, field: "photoId")
        }
        for profile in profiles {
            if let photoID = profile.avatarPhotoSourceID, !photoIDs.contains(photoID) {
                brokenReference(.profile, sourceID: profile.sourceID, field: "avatarPhotoId")
            }
        }
        for list in restaurantLists {
            if let photoID = list.customCoverPhotoSourceID, !photoIDs.contains(photoID) {
                brokenReference(.restaurantList, sourceID: list.sourceID, field: "customCoverPhotoId")
            }
        }
        for item in restaurantListItems {
            if !listIDs.contains(item.sourceListID) {
                brokenReference(.restaurantListItem, sourceID: item.sourceID, field: "listId")
            }
            if !restaurantIDs.contains(item.sourceRestaurantID) {
                brokenReference(.restaurantListItem, sourceID: item.sourceID, field: "restaurantId")
            }
        }
    }

    mutating func brokenReference(
        _ entityType: LegacyBackupEntityType,
        sourceID: String,
        field: String
    ) {
        issues.add(
            severity: .blocking,
            category: .brokenReference,
            code: .brokenReference,
            entityType: entityType,
            sourceRecordID: sourceID,
            field: field
        )
    }

    mutating func duplicateID(
        _ sourceID: String,
        entityType: LegacyBackupEntityType
    ) {
        issues.add(
            severity: .blocking,
            category: .ambiguousMapping,
            code: .duplicateSourceID,
            entityType: entityType,
            sourceRecordID: sourceID,
            field: "id"
        )
    }

    mutating func tombstoneTimestamp(
        _ object: [String: Any],
        field: String,
        entityType: LegacyBackupEntityType,
        sourceID: String
    ) -> BackupTimestampV1? {
        guard hasNonNullValue(field, in: object) else { return nil }
        guard let value = object[field] as? String,
              let timestamp = LegacyValueNormalization.timestamp(value) else {
            issues.add(
                severity: .blocking,
                category: .invalidRecord,
                code: .invalidField,
                entityType: entityType,
                sourceRecordID: sourceID,
                field: field
            )
            return nil
        }
        return timestamp
    }

    mutating func recordTombstoneReduction(
        entityType: LegacyBackupEntityType,
        sourceID: String
    ) {
        issues.add(
            severity: .info,
            category: .normalization,
            code: .deletedRecordReducedToTombstone,
            entityType: entityType,
            sourceRecordID: sourceID,
            field: "deletedAt"
        )
    }

    func hasNonNullValue(_ field: String, in object: [String: Any]) -> Bool {
        guard let value = object[field] else { return false }
        return !(value is NSNull)
    }
}

private nonisolated extension LegacyNormalizationState {
    static let profileFields: Set<String> = [
        "id", "nickname", "bio", "city", "avatarImageData", "avatarPhotoId",
        "avatarPresetId", "mapVisibility", "createdAt", "updatedAt", "deletedAt",
    ]

    mutating func convertProfiles() {
        for record in raw.users {
            guard let object = record.object else {
                issues.add(
                    severity: .blocking,
                    category: .invalidRecord,
                    code: .invalidRecord,
                    entityType: .profile
                )
                continue
            }
            let sourceID = LegacyRecordParsing.requiredID(
                object,
                entityType: .profile,
                issues: &issues
            )
            LegacyRecordParsing.inspectFields(
                object,
                allowed: Self.profileFields,
                specializedDiscarded: ["avatarImageData"],
                entityType: .profile,
                sourceID: sourceID,
                issues: &issues
            )
            guard let sourceID else { continue }
            guard seenProfileIDs.insert(sourceID).inserted else {
                duplicateID(sourceID, entityType: .profile)
                continue
            }
            if let inlineBytes = LegacyRecordParsing.inlineApproximateBytes(object["avatarImageData"]) {
                issues.add(
                    severity: .warning,
                    category: .inlineBinary,
                    code: .inlineBinaryDiscarded,
                    entityType: .profile,
                    sourceRecordID: sourceID,
                    field: "avatarImageData",
                    approximateByteCount: inlineBytes
                )
            }
            if let deletedAt = tombstoneTimestamp(
                object,
                field: "deletedAt",
                entityType: .profile,
                sourceID: sourceID
            ) {
                tombstones.append(.init(
                    sourceLineage: .legacyWebV4,
                    entityType: .profile,
                    sourceID: sourceID,
                    deletedAt: deletedAt
                ))
                recordTombstoneReduction(entityType: .profile, sourceID: sourceID)
                continue
            } else if hasNonNullValue("deletedAt", in: object) {
                continue
            }
            profiles.append(.init(
                sourceLineage: .legacyWebV4,
                sourceID: sourceID,
                displayName: LegacyRecordParsing.string(
                    "nickname", from: object, entityType: .profile, sourceID: sourceID,
                    maxUTF8: 500, issues: &issues
                ),
                bio: LegacyRecordParsing.string(
                    "bio", from: object, entityType: .profile, sourceID: sourceID,
                    maxUTF8: 20_000, issues: &issues
                ),
                city: LegacyRecordParsing.string(
                    "city", from: object, entityType: .profile, sourceID: sourceID,
                    maxUTF8: 500, issues: &issues
                ),
                avatarPhotoSourceID: LegacyRecordParsing.string(
                    "avatarPhotoId", from: object, entityType: .profile,
                    sourceID: sourceID, maxUTF8: 512, trim: true,
                    allowEmpty: false, issues: &issues
                ),
                avatarPresetID: LegacyRecordParsing.enumValue(
                    BackupProfileAvatarPresetV1.self, field: "avatarPresetId", from: object,
                    entityType: .profile, sourceID: sourceID, issues: &issues
                ),
                visibility: LegacyRecordParsing.enumValue(
                    BackupVisibilityV1.self, field: "mapVisibility", from: object,
                    entityType: .profile, sourceID: sourceID, issues: &issues
                ),
                createdAt: LegacyRecordParsing.timestamp(
                    "createdAt", from: object, entityType: .profile,
                    sourceID: sourceID, issues: &issues
                ),
                updatedAt: LegacyRecordParsing.timestamp(
                    "updatedAt", from: object, entityType: .profile,
                    sourceID: sourceID, issues: &issues
                )
            ))
        }
        if profiles.count > 1 {
            issues.add(
                severity: .requiresReview,
                category: .ambiguousMapping,
                code: .multipleProfilesRequireReview,
                entityType: .profile,
                count: profiles.count
            )
        }
    }

    static let listFields: Set<String> = [
        "id", "title", "description", "visibility", "isRanked", "coverMode",
        "customCoverImageData", "customCoverPhotoId", "createdAt", "updatedAt", "deletedAt",
    ]
    static let listItemFields: Set<String> = [
        "id", "listId", "restaurantId", "position", "note", "createdAt", "updatedAt", "deletedAt",
    ]

    mutating func convertRestaurantLists() {
        for record in raw.restaurantLists {
            guard let object = record.object else {
                issues.add(
                    severity: .blocking,
                    category: .invalidRecord,
                    code: .invalidRecord,
                    entityType: .restaurantList
                )
                continue
            }
            let sourceID = LegacyRecordParsing.requiredID(
                object, entityType: .restaurantList, issues: &issues
            )
            LegacyRecordParsing.inspectFields(
                object,
                allowed: Self.listFields,
                specializedDiscarded: ["customCoverImageData"],
                entityType: .restaurantList,
                sourceID: sourceID,
                issues: &issues
            )
            guard let sourceID else { continue }
            guard seenListIDs.insert(sourceID).inserted else {
                duplicateID(sourceID, entityType: .restaurantList)
                continue
            }
            if let inlineBytes = LegacyRecordParsing.inlineApproximateBytes(object["customCoverImageData"]) {
                issues.add(
                    severity: .warning,
                    category: .inlineBinary,
                    code: .inlineBinaryDiscarded,
                    entityType: .restaurantList,
                    sourceRecordID: sourceID,
                    field: "customCoverImageData",
                    approximateByteCount: inlineBytes
                )
            }
            if let deletedAt = tombstoneTimestamp(
                object, field: "deletedAt", entityType: .restaurantList, sourceID: sourceID
            ) {
                tombstones.append(.init(
                    sourceLineage: .legacyWebV4,
                    entityType: .restaurantList,
                    sourceID: sourceID,
                    deletedAt: deletedAt
                ))
                recordTombstoneReduction(entityType: .restaurantList, sourceID: sourceID)
                continue
            } else if hasNonNullValue("deletedAt", in: object) {
                continue
            }
            guard let title = LegacyRecordParsing.string(
                "title", from: object, entityType: .restaurantList, sourceID: sourceID,
                maxUTF8: 1_000, required: true, trim: true, allowEmpty: false,
                issues: &issues
            ) else { continue }
            restaurantLists.append(.init(
                sourceLineage: .legacyWebV4,
                sourceID: sourceID,
                title: title,
                listDescription: LegacyRecordParsing.string(
                    "description", from: object, entityType: .restaurantList,
                    sourceID: sourceID, maxUTF8: 20_000, issues: &issues
                ),
                visibility: LegacyRecordParsing.enumValue(
                    BackupVisibilityV1.self, field: "visibility", from: object,
                    entityType: .restaurantList, sourceID: sourceID, issues: &issues
                ),
                isRanked: LegacyRecordParsing.bool(
                    "isRanked", from: object, entityType: .restaurantList,
                    sourceID: sourceID, issues: &issues
                ),
                coverMode: LegacyRecordParsing.enumValue(
                    BackupRestaurantListCoverModeV1.self, field: "coverMode", from: object,
                    entityType: .restaurantList, sourceID: sourceID, issues: &issues
                ),
                customCoverPhotoSourceID: LegacyRecordParsing.string(
                    "customCoverPhotoId", from: object, entityType: .restaurantList,
                    sourceID: sourceID, maxUTF8: 512, trim: true,
                    allowEmpty: false, issues: &issues
                ),
                createdAt: LegacyRecordParsing.timestamp(
                    "createdAt", from: object, entityType: .restaurantList,
                    sourceID: sourceID, issues: &issues
                ),
                updatedAt: LegacyRecordParsing.timestamp(
                    "updatedAt", from: object, entityType: .restaurantList,
                    sourceID: sourceID, issues: &issues
                )
            ))
        }

        for record in raw.restaurantListItems {
            guard let object = record.object else {
                issues.add(
                    severity: .blocking,
                    category: .invalidRecord,
                    code: .invalidRecord,
                    entityType: .restaurantListItem
                )
                continue
            }
            let sourceID = LegacyRecordParsing.requiredID(
                object, entityType: .restaurantListItem, issues: &issues
            )
            LegacyRecordParsing.inspectFields(
                object,
                allowed: Self.listItemFields,
                entityType: .restaurantListItem,
                sourceID: sourceID,
                issues: &issues
            )
            guard let sourceID else { continue }
            guard seenListItemIDs.insert(sourceID).inserted else {
                duplicateID(sourceID, entityType: .restaurantListItem)
                continue
            }
            if let deletedAt = tombstoneTimestamp(
                object, field: "deletedAt", entityType: .restaurantListItem, sourceID: sourceID
            ) {
                tombstones.append(.init(
                    sourceLineage: .legacyWebV4,
                    entityType: .restaurantListItem,
                    sourceID: sourceID,
                    deletedAt: deletedAt
                ))
                recordTombstoneReduction(entityType: .restaurantListItem, sourceID: sourceID)
                continue
            } else if hasNonNullValue("deletedAt", in: object) {
                continue
            }
            guard let listID = LegacyRecordParsing.string(
                "listId", from: object, entityType: .restaurantListItem,
                sourceID: sourceID, maxUTF8: 512, required: true,
                trim: true, allowEmpty: false, issues: &issues
            ), let restaurantID = LegacyRecordParsing.string(
                "restaurantId", from: object, entityType: .restaurantListItem,
                sourceID: sourceID, maxUTF8: 512, required: true,
                trim: true, allowEmpty: false, issues: &issues
            ) else { continue }
            restaurantListItems.append(.init(
                sourceLineage: .legacyWebV4,
                sourceID: sourceID,
                sourceListID: listID,
                sourceRestaurantID: restaurantID,
                position: LegacyRecordParsing.integer(
                    "position", from: object, entityType: .restaurantListItem,
                    sourceID: sourceID, minimum: 0, issues: &issues
                ),
                note: LegacyRecordParsing.string(
                    "note", from: object, entityType: .restaurantListItem,
                    sourceID: sourceID, maxUTF8: 20_000, issues: &issues
                ),
                createdAt: LegacyRecordParsing.timestamp(
                    "createdAt", from: object, entityType: .restaurantListItem,
                    sourceID: sourceID, issues: &issues
                ),
                updatedAt: LegacyRecordParsing.timestamp(
                    "updatedAt", from: object, entityType: .restaurantListItem,
                    sourceID: sourceID, issues: &issues
                )
            ))
        }
    }
}

private nonisolated extension LegacyNormalizationState {
    static let visitFields: Set<String> = [
        "id", "restaurantId", "visitedAt", "rating", "visibility", "diningMode",
        "totalPrice", "myActualSpend", "paymentMode", "pricePerPerson", "partySize",
        "queueDuration", "diningOccasions", "diningOccasion", "diningOccasionText",
        "valueRating", "environmentRating", "serviceRating", "valueTags",
        "environmentTags", "serviceTags", "noiseLevel", "diningDuration",
        "portionLevel", "transportConvenience", "specialNotes",
        "recommendationSourceType", "recommendationSourceText", "sharedMealId",
        "companions", "companionIds", "dishes", "note", "photos", "photoIds",
        "createdAt", "updatedAt", "deletedAt",
    ]

    static let deprecatedVisitFields: Set<String> = [
        "willingToReturn", "willingToVisitAgain", "wouldReturn", "returnWillingness",
        "revisitIntent", "recommendedDishes", "recommendedDishIds", "recommendedDishNames",
        "recommendDishes", "avoidDishes", "avoidDishIds", "avoidDishNames",
        "seatSituation", "seating", "seatingSituation", "seatDetails",
        "reservation", "reservationDetails", "reservationRequired", "reservationNotes",
        "bestVisitTime", "bestTimeToVisit", "recommendedVisitTime",
    ]

    mutating func convertVisitsAndEmbeddedEntities() {
        for record in raw.visits {
            guard let object = record.object else {
                issues.add(
                    severity: .blocking,
                    category: .invalidRecord,
                    code: .invalidRecord,
                    entityType: .visit
                )
                continue
            }
            let sourceID = LegacyRecordParsing.requiredID(
                object,
                entityType: .visit,
                issues: &issues
            )
            LegacyRecordParsing.inspectFields(
                object,
                allowed: Self.visitFields,
                deprecated: Self.deprecatedVisitFields,
                specializedDiscarded: ["photos", "companionIds"],
                entityType: .visit,
                sourceID: sourceID,
                issues: &issues
            )
            if object["recommendationSourceUserId"] != nil {
                issues.add(
                    severity: .warning,
                    category: .securityAuthority,
                    code: .linkedSocialIdentityRemoved,
                    entityType: .visit,
                    field: "recommendationSourceUserId"
                )
            }
            guard let sourceID else { continue }
            guard seenVisitIDs.insert(sourceID).inserted else {
                duplicateID(sourceID, entityType: .visit)
                continue
            }
            if let deletedAt = tombstoneTimestamp(
                object,
                field: "deletedAt",
                entityType: .visit,
                sourceID: sourceID
            ) {
                tombstones.append(.init(
                    sourceLineage: .legacyWebV4,
                    entityType: .visit,
                    sourceID: sourceID,
                    deletedAt: deletedAt
                ))
                recordTombstoneReduction(entityType: .visit, sourceID: sourceID)
                continue
            } else if hasNonNullValue("deletedAt", in: object) {
                continue
            }

            guard let restaurantID = LegacyRecordParsing.string(
                "restaurantId", from: object, entityType: .visit, sourceID: sourceID,
                maxUTF8: 512, required: true, trim: true, allowEmpty: false,
                issues: &issues
            ) else {
                continue
            }
            let visitedAt = LegacyRecordParsing.timestamp(
                "visitedAt", from: object, entityType: .visit,
                sourceID: sourceID, issues: &issues
            )
            let sourceType = LegacyRecordParsing.enumValue(
                BackupRecommendationSourceTypeV1.self,
                field: "recommendationSourceType",
                from: object,
                entityType: .visit,
                sourceID: sourceID,
                issues: &issues
            )
            let sourceText = LegacyRecordParsing.string(
                "recommendationSourceText", from: object, entityType: .visit,
                sourceID: sourceID, maxUTF8: 2_000, issues: &issues
            )
            let sharedMealHint = LegacyRecordParsing.string(
                "sharedMealId", from: object, entityType: .visit, sourceID: sourceID,
                maxUTF8: 512, trim: true, allowEmpty: false, issues: &issues
            )
            if sharedMealHint != nil {
                issues.add(
                    severity: .warning,
                    category: .ignoredSocialData,
                    code: .sharedMealReferenceIsNonAuthoritative,
                    entityType: .visit,
                    sourceRecordID: sourceID,
                    field: "sharedMealId"
                )
            }

            let visit = LegacyStagingVisit(
                sourceLineage: .legacyWebV4,
                sourceID: sourceID,
                sourceRestaurantID: restaurantID,
                visitedAt: visitedAt,
                diningMode: LegacyRecordParsing.enumValue(
                    BackupDiningModeV1.self, field: "diningMode", from: object,
                    entityType: .visit, sourceID: sourceID, required: true, issues: &issues
                ),
                visibility: LegacyRecordParsing.enumValue(
                    BackupVisibilityV1.self, field: "visibility", from: object,
                    entityType: .visit, sourceID: sourceID, required: true, issues: &issues
                ),
                totalPrice: LegacyRecordParsing.money(
                    "totalPrice", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                myActualSpend: LegacyRecordParsing.money(
                    "myActualSpend", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                paymentMode: LegacyRecordParsing.enumValue(
                    BackupPaymentModeV1.self, field: "paymentMode", from: object,
                    entityType: .visit, sourceID: sourceID, issues: &issues
                ),
                pricePerPerson: LegacyRecordParsing.money(
                    "pricePerPerson", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                partySize: LegacyRecordParsing.integer(
                    "partySize", from: object, entityType: .visit,
                    sourceID: sourceID, minimum: 1, issues: &issues
                ),
                queueDuration: LegacyRecordParsing.enumValue(
                    BackupQueueDurationV1.self, field: "queueDuration", from: object,
                    entityType: .visit, sourceID: sourceID, issues: &issues
                ),
                diningOccasions: diningOccasions(object, visitID: sourceID),
                diningOccasionText: LegacyRecordParsing.string(
                    "diningOccasionText", from: object, entityType: .visit,
                    sourceID: sourceID, maxUTF8: 2_000, issues: &issues
                ),
                rating: LegacyRecordParsing.rating(
                    "rating", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                valueRating: LegacyRecordParsing.rating(
                    "valueRating", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                environmentRating: LegacyRecordParsing.rating(
                    "environmentRating", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                serviceRating: LegacyRecordParsing.rating(
                    "serviceRating", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                valueTags: LegacyRecordParsing.stringArray(
                    "valueTags", from: object, entityType: .visit, sourceID: sourceID,
                    maxItemUTF8: 200, issues: &issues
                ),
                environmentTags: LegacyRecordParsing.stringArray(
                    "environmentTags", from: object, entityType: .visit, sourceID: sourceID,
                    maxItemUTF8: 200, issues: &issues
                ),
                serviceTags: LegacyRecordParsing.stringArray(
                    "serviceTags", from: object, entityType: .visit, sourceID: sourceID,
                    maxItemUTF8: 200, issues: &issues
                ),
                noiseLevel: LegacyRecordParsing.enumValue(
                    BackupNoiseLevelV1.self, field: "noiseLevel", from: object,
                    entityType: .visit, sourceID: sourceID, issues: &issues
                ),
                diningDuration: LegacyRecordParsing.enumValue(
                    BackupDiningDurationV1.self, field: "diningDuration", from: object,
                    entityType: .visit, sourceID: sourceID, issues: &issues
                ),
                portionLevel: LegacyRecordParsing.enumValue(
                    BackupPortionLevelV1.self, field: "portionLevel", from: object,
                    entityType: .visit, sourceID: sourceID, issues: &issues
                ),
                transportConvenience: LegacyRecordParsing.enumValue(
                    BackupTransportConvenienceV1.self, field: "transportConvenience", from: object,
                    entityType: .visit, sourceID: sourceID, issues: &issues
                ),
                specialNotes: LegacyRecordParsing.string(
                    "specialNotes", from: object, entityType: .visit,
                    sourceID: sourceID, maxUTF8: 20_000, issues: &issues
                ),
                recommendationSourceID: nil,
                recommendationSourceType: sourceType,
                recommendationSourceText: sourceText,
                sharedMealReferenceHint: sharedMealHint,
                companionSourceIDs: [],
                note: LegacyRecordParsing.string(
                    "note", from: object, entityType: .visit,
                    sourceID: sourceID, maxUTF8: 50_000, issues: &issues
                ),
                createdAt: LegacyRecordParsing.timestamp(
                    "createdAt", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                ),
                updatedAt: LegacyRecordParsing.timestamp(
                    "updatedAt", from: object, entityType: .visit,
                    sourceID: sourceID, issues: &issues
                )
            )
            visits.append(visit)
            convertCompanions(object, visit: visit)
            convertRecommendationSource(visit: visit)
            convertEmbeddedDishes(object, visit: visit)
            collectVisitPhotoReferences(object, visitID: sourceID)
        }
    }

    mutating func diningOccasions(
        _ object: [String: Any],
        visitID: String
    ) -> [BackupDiningOccasionV1]? {
        var result: [BackupDiningOccasionV1]? = nil
        if let raw = object["diningOccasions"], !(raw is NSNull) {
            guard let array = raw as? [Any] else {
                LegacyRecordParsing.invalid(
                    "diningOccasions", entityType: .visit,
                    sourceID: visitID, issues: &issues
                )
                return nil
            }
            result = []
            for value in array {
                guard let rawValue = value as? String,
                      let occasion = BackupDiningOccasionV1(rawValue: rawValue) else {
                    LegacyRecordParsing.invalid(
                        "diningOccasions", entityType: .visit,
                        sourceID: visitID, issues: &issues
                    )
                    continue
                }
                if !(result?.contains(where: { $0.rawValue == occasion.rawValue }) ?? false) {
                    result?.append(occasion)
                }
            }
        }
        if let singular = LegacyRecordParsing.enumValue(
            BackupDiningOccasionV1.self,
            field: "diningOccasion",
            from: object,
            entityType: .visit,
            sourceID: visitID,
            issues: &issues
        ) {
            if result == nil { result = [] }
            if !(result?.contains(where: { $0.rawValue == singular.rawValue }) ?? false) {
                result?.append(singular)
            }
        }
        return result
    }

    mutating func convertCompanions(
        _ object: [String: Any],
        visit: LegacyStagingVisit
    ) {
        let names = LegacyRecordParsing.stringArray(
            "companions", from: object, entityType: .visit, sourceID: visit.sourceID,
            maxItemUTF8: 500, trim: true, issues: &issues
        ) ?? []
        var visitIDs: [String] = []
        for name in names {
            let displayName = LegacyValueNormalization.normalizedName(name)
            guard !displayName.isEmpty else {
                LegacyRecordParsing.invalid(
                    "companions", entityType: .visit,
                    sourceID: visit.sourceID, issues: &issues
                )
                continue
            }
            let key = LegacyValueNormalization.stableLookupKey(displayName)
            let sourceID = LegacyRecordParsing.stableHashedSourceID(
                namespace: "companion",
                key: "\(raw.sourceMetadata.sourceFingerprint)|\(key)"
            )
            if var existing = companionAccumulators[key] {
                existing.observe(visit.visitedAt)
                companionAccumulators[key] = existing
            } else {
                companionAccumulators[key] = LegacyNamedEntityAccumulator(
                    sourceID: sourceID,
                    displayName: displayName,
                    firstObservedAt: visit.visitedAt,
                    lastObservedAt: visit.visitedAt
                )
            }
            if !visitIDs.contains(sourceID) { visitIDs.append(sourceID) }
        }
        companionIDsByVisit[visit.sourceID] = visitIDs.sorted()
        if let linkedIDs = object["companionIds"] as? [Any], !linkedIDs.isEmpty {
            issues.add(
                severity: .warning,
                category: .securityAuthority,
                code: .linkedSocialIdentityRemoved,
                entityType: .visit,
                field: "companionIds",
                count: linkedIDs.count
            )
        }
    }

    mutating func convertRecommendationSource(visit: LegacyStagingVisit) {
        guard let rawText = visit.recommendationSourceText else { return }
        let displayName = LegacyValueNormalization.normalizedName(rawText)
        guard !displayName.isEmpty else { return }
        let sourceTypeKey = visit.recommendationSourceType?.rawValue ?? "unknown"
        let key = "\(sourceTypeKey)|\(LegacyValueNormalization.stableLookupKey(displayName))"
        let sourceID = LegacyRecordParsing.stableHashedSourceID(
            namespace: "recommendation-source",
            key: "\(raw.sourceMetadata.sourceFingerprint)|\(key)"
        )
        if var existing = recommendationSourceAccumulators[key] {
            existing.observe(visit.visitedAt)
            recommendationSourceAccumulators[key] = existing
        } else {
            recommendationSourceAccumulators[key] = LegacyRecommendationSourceAccumulator(
                sourceID: sourceID,
                displayName: displayName,
                sourceType: visit.recommendationSourceType,
                firstObservedAt: visit.visitedAt,
                lastObservedAt: visit.visitedAt
            )
        }
        recommendationSourceIDByVisit[visit.sourceID] = sourceID
    }

    mutating func convertEmbeddedDishes(
        _ object: [String: Any],
        visit: LegacyStagingVisit
    ) {
        guard let rawDishes = object["dishes"], !(rawDishes is NSNull) else { return }
        guard let array = rawDishes as? [Any] else {
            LegacyRecordParsing.invalid(
                "dishes", entityType: .visit,
                sourceID: visit.sourceID, issues: &issues
            )
            return
        }
        for (index, value) in array.enumerated() {
            guard let dishObject = value as? [String: Any] else {
                issues.add(
                    severity: .warning,
                    category: .invalidRecord,
                    code: .invalidRecord,
                    entityType: .dish,
                    sourceRecordID: visit.sourceID
                )
                continue
            }
            let sourceID = "legacy-dish:\(visit.sourceID):index:\(index)"
            LegacyRecordParsing.inspectFields(
                dishObject,
                allowed: ["id", "name", "taste", "rating", "price", "imageData", "photoId"],
                specializedDiscarded: ["imageData"],
                entityType: .dish,
                sourceID: sourceID,
                issues: &issues
            )
            if let inlineBytes = LegacyRecordParsing.inlineApproximateBytes(dishObject["imageData"]) {
                issues.add(
                    severity: .warning,
                    category: .inlineBinary,
                    code: .inlineBinaryDiscarded,
                    entityType: .dish,
                    sourceRecordID: sourceID,
                    field: "imageData",
                    approximateByteCount: inlineBytes
                )
            }
            guard let name = LegacyRecordParsing.string(
                "name", from: dishObject, entityType: .dish, sourceID: sourceID,
                maxUTF8: 500, required: true, trim: true, allowEmpty: false,
                issues: &issues
            ) else { continue }
            let legacyDishID = LegacyRecordParsing.string(
                "id", from: dishObject, entityType: .dish, sourceID: sourceID,
                maxUTF8: 512, trim: true, allowEmpty: false, issues: &issues
            )
            let photoID = LegacyRecordParsing.string(
                "photoId", from: dishObject, entityType: .dish, sourceID: sourceID,
                maxUTF8: 512, trim: true, allowEmpty: false, issues: &issues
            )
            dishes.append(.init(
                sourceLineage: .legacyWebV4,
                sourceID: sourceID,
                sourceLegacyDishID: legacyDishID,
                sourceRestaurantID: visit.sourceRestaurantID,
                sourceVisitID: visit.sourceID,
                name: name,
                sourcePhotoID: photoID
            ))
            visitDishes.append(.init(
                sourceLineage: .legacyWebV4,
                sourceID: "legacy-visit-dish:\(visit.sourceID):index:\(index)",
                sourceVisitID: visit.sourceID,
                sourceRestaurantID: visit.sourceRestaurantID,
                sourceDishID: sourceID,
                tasteNote: LegacyRecordParsing.string(
                    "taste", from: dishObject, entityType: .visitDish, sourceID: sourceID,
                    maxUTF8: 20_000, issues: &issues
                ),
                rating: LegacyRecordParsing.rating(
                    "rating", from: dishObject, entityType: .visitDish,
                    sourceID: sourceID, issues: &issues
                ),
                price: LegacyRecordParsing.money(
                    "price", from: dishObject, entityType: .visitDish,
                    sourceID: sourceID, issues: &issues
                ),
                sourceOrder: index
            ))
            if let photoID {
                dishPhotoReferences.append((dishID: sourceID, photoID: photoID))
            }
        }
    }

    mutating func collectVisitPhotoReferences(
        _ object: [String: Any],
        visitID: String
    ) {
        if let inlinePhotos = object["photos"] as? [Any] {
            let bytes = inlinePhotos.reduce(0) { partial, value in
                partial + (LegacyRecordParsing.inlineApproximateBytes(value) ?? 0)
            }
            if !inlinePhotos.isEmpty {
                issues.add(
                    severity: .warning,
                    category: .inlineBinary,
                    code: .inlineBinaryDiscarded,
                    entityType: .visit,
                    sourceRecordID: visitID,
                    field: "photos",
                    count: inlinePhotos.count,
                    approximateByteCount: bytes
                )
            }
        } else if hasNonNullValue("photos", in: object) {
            LegacyRecordParsing.invalid(
                "photos", entityType: .visit,
                sourceID: visitID, issues: &issues
            )
        }
        guard let photoIDs = object["photoIds"], !(photoIDs is NSNull) else { return }
        guard let array = photoIDs as? [Any] else {
            LegacyRecordParsing.invalid(
                "photoIds", entityType: .visit,
                sourceID: visitID, issues: &issues
            )
            return
        }
        for value in array {
            if value is NSNull { continue }
            guard let rawID = value as? String else {
                LegacyRecordParsing.invalid(
                    "photoIds", entityType: .visit,
                    sourceID: visitID, issues: &issues
                )
                continue
            }
            let photoID = LegacyValueNormalization.normalizedName(rawID)
            guard !photoID.isEmpty, photoID.utf8.count <= 512 else {
                LegacyRecordParsing.invalid(
                    "photoIds", entityType: .visit,
                    sourceID: visitID, issues: &issues
                )
                continue
            }
            visitPhotoReferences.append((visitID: visitID, photoID: photoID))
        }
    }
}
