import CryptoKit
import Foundation

nonisolated struct BackupImportPlanEngine: Sendable {
    func makePlan(
        source: BackupImportSourceGraph,
        local: BackupImportLocalSnapshot,
        decisions: [BackupImportReviewDecision] = [],
        generatedAt: Date = .now,
        snapshotSeconds: Double = 0
    ) throws -> BackupImportPlan {
        guard source.sourceFileSHA256.count == 64 else {
            throw BackupImportPlanningError.sourceHashMismatch
        }
        guard local.currentTasteMapUserID.range(
            of: #"^tm_[A-Za-z0-9_-]{3,120}$"#,
            options: .regularExpression
        ) != nil else { throw BackupImportPlanningError.invalidCurrentUser }
        for decision in decisions {
            guard decision.sourceFileSHA256 == source.sourceFileSHA256,
                  decision.localSnapshotRevision == local.revision else {
                throw BackupImportPlanningError.invalidDecision
            }
        }

        let clock = ContinuousClock()
        let matchingStart = clock.now
        let decisionIndex = Dictionary(uniqueKeysWithValues: decisions.map { ($0.reviewItemID, $0) })
        var actions: [BackupImportPlannedAction] = []
        var reviewItems: [ImportPlanReviewItem] = []
        var warnings: [String] = []

        let sourceTombstones = Set(source.tombstones.map { "\($0.entityType.rawValue):\($0.sourceID)" })
        let restaurantResult = try planRestaurants(
            source: source.restaurants,
            local: local.restaurants,
            sourceHash: source.sourceFileSHA256,
            localRevision: local.revision,
            decisionIndex: decisionIndex
        )
        actions.append(contentsOf: restaurantResult.actions)
        reviewItems.append(contentsOf: restaurantResult.reviews)
        let restaurantActions = Dictionary(uniqueKeysWithValues: restaurantResult.actions.map { ($0.sourceID, $0) })

        let companionResult = try planCompanions(
            source: source.companions,
            local: local.companions,
            sourceHash: source.sourceFileSHA256
        )
        actions.append(contentsOf: companionResult)

        let sourceResult = try planRecommendationSources(
            source: source.recommendationSources,
            local: local.recommendationSources,
            sourceHash: source.sourceFileSHA256
        )
        actions.append(contentsOf: sourceResult)

        let visitResult = try planVisits(
            source: source.visits,
            local: local.visits,
            localRestaurants: local.restaurants,
            localCompanions: local.companions,
            localRecommendationSources: local.recommendationSources,
            restaurantActions: restaurantActions,
            companionActions: Dictionary(uniqueKeysWithValues: companionResult.map { ($0.sourceID, $0) }),
            recommendationSourceActions: Dictionary(uniqueKeysWithValues: sourceResult.map { ($0.sourceID, $0) }),
            sourceHash: source.sourceFileSHA256,
            localRevision: local.revision,
            decisionIndex: decisionIndex
        )
        actions.append(contentsOf: visitResult.actions)
        reviewItems.append(contentsOf: visitResult.reviews)
        let visitActions = Dictionary(uniqueKeysWithValues: visitResult.actions.map { ($0.sourceID, $0) })

        let dishResult = try planDishes(
            source: source.dishes,
            local: local.dishes,
            localRestaurants: local.restaurants,
            localVisits: local.visits,
            restaurantActions: restaurantActions,
            visitActions: visitActions,
            sourceHash: source.sourceFileSHA256,
            localRevision: local.revision,
            decisionIndex: decisionIndex
        )
        actions.append(contentsOf: dishResult.actions)
        reviewItems.append(contentsOf: dishResult.reviews)
        let dishActions = Dictionary(uniqueKeysWithValues: dishResult.actions.map { ($0.sourceID, $0) })

        actions.append(contentsOf: planVisitDishes(
            source: source.visitDishes,
            local: local.visitDishes,
            localVisits: local.visits,
            localDishes: local.dishes,
            restaurantActions: restaurantActions,
            visitActions: visitActions,
            dishActions: dishActions,
            sourceHash: source.sourceFileSHA256
        ))

        let profileResult = try planProfiles(
            source: source.profiles,
            local: local.profiles,
            sourceHash: source.sourceFileSHA256,
            localRevision: local.revision,
            decisionIndex: decisionIndex
        )
        actions.append(contentsOf: profileResult.actions)
        reviewItems.append(contentsOf: profileResult.reviews)

        let listResult = try planLists(
            source: source.restaurantLists,
            local: local.restaurantLists,
            sourceHash: source.sourceFileSHA256,
            localRevision: local.revision,
            decisionIndex: decisionIndex
        )
        actions.append(contentsOf: listResult.actions)
        reviewItems.append(contentsOf: listResult.reviews)
        let listActions = Dictionary(uniqueKeysWithValues: listResult.actions.map { ($0.sourceID, $0) })

        actions.append(contentsOf: planListItems(
            source: source.restaurantListItems,
            local: local.restaurantListItems,
            localLists: local.restaurantLists,
            localRestaurants: local.restaurants,
            listActions: listActions,
            restaurantActions: restaurantActions,
            sourceHash: source.sourceFileSHA256
        ))

        for photo in source.photos.sorted(by: { $0.sourceID < $1.sourceID }) {
            actions.append(action(
                .photo,
                photo.sourceID,
                nil,
                nil,
                .skip,
                "missingBinary",
                photo.fileName ?? "照片记录",
                [photo.parentSourceID]
            ))
        }
        if !source.photos.isEmpty {
            warnings.append("\(source.photos.count) 个照片记录和相关引用将被跳过，因为备份不包含可恢复的原图或安全 storage locator。")
        }

        for tombstone in source.tombstones.sorted(by: {
            ($0.entityType.rawValue, $0.sourceID) < ($1.entityType.rawValue, $1.sourceID)
        }) {
            actions.append(action(
                tombstone.entityType,
                tombstone.sourceID,
                nil,
                nil,
                .skip,
                "ignoreSourceTombstone",
                "已删除记录",
                []
            ))
        }
        if !sourceTombstones.isEmpty {
            warnings.append("\(sourceTombstones.count) 个来源 Tombstone 只作为负面证据，不会删除当前本地数据。")
        }

        actions.sort(by: Self.actionSort)
        reviewItems.sort { $0.id < $1.id }
        warnings = Array(Set(warnings)).sorted()
        let summaries = BackupImportEntityKind.allCases.map { entityType in
            let values = actions.filter { $0.entityType == entityType }
            return BackupImportEntityActionSummary(
                entityType: entityType,
                create: values.filter { $0.action == .create }.count,
                exactMerge: values.filter { $0.action == .exactMerge }.count,
                exactDuplicate: values.filter { $0.action == .exactDuplicate }.count,
                review: values.filter { $0.action == .userReviewRequired }.count,
                skipped: values.filter { $0.action == .skip }.count,
                blocked: values.filter { $0.action == .blocked }.count
            )
        }
        let matchingSeconds = Self.seconds(matchingStart.duration(to: clock.now))
        let summary = BackupImportPlanSummary(
            entities: summaries,
            estimatedMutationCount: actions.filter { $0.action == .create || $0.action == .exactMerge }.count,
            warningCount: warnings.count,
            reviewCount: reviewItems.count,
            blockerCount: actions.filter { $0.action == .blocked }.count
        )
        return BackupImportPlan(
            planID: Self.deterministicUUID(
                "plan|\(source.sourceFileSHA256)|\(local.currentTasteMapUserID)|\(local.revision)"
            ),
            sourceFileSHA256: source.sourceFileSHA256,
            sourceFormat: source.sourceFormat,
            currentTasteMapUserID: local.currentTasteMapUserID,
            generatedAt: generatedAt,
            localSnapshotRevision: local.revision,
            actions: actions,
            reviewItems: reviewItems,
            warnings: warnings,
            summary: summary,
            timing: BackupImportPlanTiming(
                snapshotSeconds: max(0, snapshotSeconds),
                matchingSeconds: matchingSeconds,
                totalSeconds: max(0, snapshotSeconds) + matchingSeconds
            )
        )
    }

    private func planRestaurants(
        source: [BackupImportSourceRestaurant],
        local: [BackupImportLocalRecord<BackupImportSourceRestaurant>],
        sourceHash: String,
        localRevision: String,
        decisionIndex: [String: BackupImportReviewDecision]
    ) throws -> (actions: [BackupImportPlannedAction], reviews: [ImportPlanReviewItem]) {
        let active = local.filter { $0.deletedAt == nil }
        let deleted = local.filter { $0.deletedAt != nil }
        var identityIndex: [String: [BackupImportLocalRecord<BackupImportSourceRestaurant>]] = [:]
        for record in active {
            for identity in record.value.placeIdentities where Self.authoritativeProvider(identity.provider) {
                identityIndex[identity.key, default: []].append(record)
            }
        }
        let deletedKeys = Set(deleted.flatMap { $0.value.placeIdentities.map(\.key) })
        let probableIndex = Dictionary(grouping: active) {
            "\(Self.normalized($0.value.name))|\(Self.normalized($0.value.city))"
        }
        var actions: [BackupImportPlannedAction] = []
        var reviews: [ImportPlanReviewItem] = []

        for value in source.sorted(by: { $0.sourceID < $1.sourceID }) {
            let deterministicTargetID = Self.targetID(sourceHash, .restaurant, value.sourceID)
            let authoritativeKeys = value.placeIdentities
                .filter { Self.authoritativeProvider($0.provider) }
                .map(\.key)
            if authoritativeKeys.contains(where: deletedKeys.contains)
                || deleted.contains(where: {
                    $0.remoteID == value.sourceID || $0.remoteID == deterministicTargetID
                        || $0.localID.uuidString.lowercased() == deterministicTargetID
                }) {
                actions.append(action(.restaurant, value.sourceID, nil, nil, .skip,
                                      "skipBecauseTombstoned", value.name, []))
                continue
            }
            if let imported = active.first(where: {
                $0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID
            }) {
                actions.append(action(
                    .restaurant,
                    value.sourceID,
                    imported.localID.uuidString.lowercased(),
                    imported.localID.uuidString.lowercased(),
                    .exactDuplicate,
                    "sameImportSourceEntity",
                    value.name,
                    []
                ))
                continue
            }
            let exactCandidates = Dictionary(
                grouping: authoritativeKeys.flatMap { identityIndex[$0] ?? [] },
                by: \.localID
            ).compactMap(\.value.first)
            if exactCandidates.count > 1 {
                actions.append(action(.restaurant, value.sourceID, nil, nil, .blocked,
                                      "providerIdentityCollision", value.name, []))
                continue
            }
            if let exact = exactCandidates.first {
                let localByProvider = Dictionary(grouping: exact.value.placeIdentities, by: \.provider)
                let incompatibleProvider = value.placeIdentities.contains { incoming in
                    guard Self.authoritativeProvider(incoming.provider) else { return false }
                    return (localByProvider[incoming.provider] ?? []).contains {
                        $0.externalID != incoming.externalID
                    }
                }
                if incompatibleProvider {
                    actions.append(action(.restaurant, value.sourceID, nil,
                                          exact.localID.uuidString.lowercased(), .blocked,
                                          "incompatibleProviderIdentity", value.name, []))
                    continue
                }
                actions.append(action(
                    .restaurant,
                    value.sourceID,
                    exact.localID.uuidString.lowercased(),
                    exact.localID.uuidString.lowercased(),
                    .exactMerge,
                    "exactProviderIdentity",
                    value.name,
                    []
                ))
                continue
            }

            let key = "\(Self.normalized(value.name))|\(Self.normalized(value.city))"
            let probable = (probableIndex[key] ?? []).filter {
                let addressMatch = !value.address.isEmpty
                    && Self.normalized(value.address) == Self.normalized($0.value.address)
                let distance = Self.distanceMeters(
                    value.latitude, value.longitude,
                    $0.value.latitude, $0.value.longitude
                )
                return addressMatch || distance <= 30
            }
            if probable.count == 1, let candidate = probable.first {
                let reviewID = "restaurant:\(value.sourceID):possibleSame"
                let candidateID = candidate.localID.uuidString.lowercased()
                let newID = deterministicTargetID
                let item = ImportPlanReviewItem(
                    id: reviewID,
                    entityType: .restaurant,
                    sourceID: value.sourceID,
                    title: "可能是同一家餐厅",
                    sourceSafeLabel: Self.restaurantLabel(value),
                    candidateSafeLabel: Self.restaurantLabel(candidate.value),
                    reason: "名称、城市与地址或位置接近，但没有相同的 provider identity。",
                    detail: "距离约 \(Int(Self.distanceMeters(value.latitude, value.longitude, candidate.value.latitude, candidate.value.longitude).rounded())) 米；provider 不同，不能自动合并。",
                    options: [
                        BackupImportReviewOption(id: "merge", kind: .merge, title: "与现有餐厅合并", targetID: candidateID),
                        BackupImportReviewOption(id: "create", kind: .create, title: "作为新餐厅导入", targetID: newID),
                        BackupImportReviewOption(id: "skip", kind: .skip, title: "跳过", targetID: nil),
                    ],
                    recommendedOptionID: "create"
                )
                if let decision = decisionIndex[reviewID] {
                    guard decision.sourceID == value.sourceID else { throw BackupImportPlanningError.invalidDecision }
                    switch decision.selectedOptionID {
                    case "merge":
                        guard decision.targetID == candidateID else { throw BackupImportPlanningError.invalidDecision }
                        actions.append(action(.restaurant, value.sourceID, candidateID, candidateID,
                                              .exactMerge, "userConfirmedMerge", value.name, []))
                    case "create":
                        guard decision.targetID == newID else { throw BackupImportPlanningError.invalidDecision }
                        actions.append(action(.restaurant, value.sourceID, newID, nil,
                                              .create, "userConfirmedNew", value.name, []))
                    case "skip":
                        guard decision.targetID == nil else { throw BackupImportPlanningError.invalidDecision }
                        actions.append(action(.restaurant, value.sourceID, nil, nil,
                                              .skip, "userSkipped", value.name, []))
                    default: throw BackupImportPlanningError.invalidDecision
                    }
                } else {
                    actions.append(action(.restaurant, value.sourceID, newID, candidateID,
                                          .userReviewRequired, "possibleSameRestaurant", value.name, []))
                    reviews.append(item)
                }
            } else {
                actions.append(action(
                    .restaurant,
                    value.sourceID,
                    deterministicTargetID,
                    nil,
                    .create,
                    probable.count > 1 ? "ambiguousChainOrBranchCreateNew" : "noExactIdentity",
                    value.name,
                    []
                ))
            }
        }
        return (actions, reviews)
    }

    private func planVisits(
        source: [BackupImportSourceVisit],
        local: [BackupImportLocalRecord<BackupImportSourceVisit>],
        localRestaurants: [BackupImportLocalRecord<BackupImportSourceRestaurant>],
        localCompanions: [BackupImportLocalRecord<BackupImportSourceCompanion>],
        localRecommendationSources: [BackupImportLocalRecord<BackupImportSourceRecommendationSource>],
        restaurantActions: [String: BackupImportPlannedAction],
        companionActions: [String: BackupImportPlannedAction],
        recommendationSourceActions: [String: BackupImportPlannedAction],
        sourceHash: String,
        localRevision: String,
        decisionIndex: [String: BackupImportReviewDecision]
    ) throws -> (actions: [BackupImportPlannedAction], reviews: [ImportPlanReviewItem]) {
        let restaurantRemoteByLocalID = Dictionary(uniqueKeysWithValues: localRestaurants.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        let companionRemoteByLocalID = Dictionary(uniqueKeysWithValues: localCompanions.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        let recommendationRemoteByLocalID = Dictionary(uniqueKeysWithValues: localRecommendationSources.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        let active = local.filter { $0.deletedAt == nil }
        let deletedIDs = Set(local.filter { $0.deletedAt != nil }.map(\.remoteID))
        let byRemoteID = Dictionary(grouping: active, by: \.remoteID)
        let fingerprintIndex = Dictionary(grouping: active) { Self.visitFingerprint($0.value) }
        var actions: [BackupImportPlannedAction] = []
        var reviews: [ImportPlanReviewItem] = []
        for value in source.sorted(by: { $0.sourceID < $1.sourceID }) {
            let deterministicTargetID = Self.targetID(sourceHash, .visit, value.sourceID)
            guard let restaurantAction = restaurantActions[value.sourceRestaurantID] else {
                actions.append(action(.visit, value.sourceID, nil, nil, .blocked,
                                      "missingRestaurantPlan", "到访记录", [value.sourceRestaurantID]))
                continue
            }
            if restaurantAction.action == .skip {
                actions.append(action(.visit, value.sourceID, nil, nil, .skip,
                                      "restaurantSkipped", "到访记录", [value.sourceRestaurantID]))
                continue
            }
            guard restaurantAction.action != .blocked,
                  restaurantAction.action != .userReviewRequired,
                  let restaurantTargetID = restaurantAction.targetID else {
                actions.append(action(.visit, value.sourceID, nil, nil, .blocked,
                                      "restaurantReviewPending", "到访记录", [value.sourceRestaurantID]))
                continue
            }
            if deletedIDs.contains(value.sourceID) || deletedIDs.contains(deterministicTargetID) {
                actions.append(action(.visit, value.sourceID, nil, nil, .skip,
                                      "skipBecauseTombstoned", "到访记录", [value.sourceRestaurantID]))
                continue
            }
            if let imported = byRemoteID[deterministicTargetID]?.first {
                actions.append(action(.visit, value.sourceID, imported.localID.uuidString.lowercased(),
                                      imported.localID.uuidString.lowercased(), .exactDuplicate,
                                      "sameImportSourceEntity", "到访记录", [value.sourceRestaurantID]))
                continue
            }
            let mappedRestaurantRemoteID = restaurantRemoteByLocalID[restaurantTargetID] ?? restaurantTargetID
            let mappedCompanionIDs = value.companionSourceIDs.compactMap { sourceID -> String? in
                guard let action = companionActions[sourceID],
                      action.action != .skip,
                      let targetID = action.targetID else { return nil }
                return companionRemoteByLocalID[targetID] ?? targetID
            }
            let mappedRecommendationID = value.recommendationSourceID.flatMap { sourceID -> String? in
                guard let action = recommendationSourceActions[sourceID],
                      action.action != .skip,
                      let targetID = action.targetID else { return nil }
                return recommendationRemoteByLocalID[targetID] ?? targetID
            }
            var mapped = value
            mapped = BackupImportSourceVisit(
                sourceID: value.sourceID,
                sourceRestaurantID: mappedRestaurantRemoteID,
                visitedAt: value.visitedAt,
                diningMode: value.diningMode,
                visibility: value.visibility,
                partySize: value.partySize,
                totalPrice: value.totalPrice,
                myActualSpend: value.myActualSpend,
                paymentMode: value.paymentMode,
                pricePerPerson: value.pricePerPerson,
                queueDuration: value.queueDuration,
                diningOccasions: value.diningOccasions,
                diningOccasionText: value.diningOccasionText,
                rating: value.rating,
                valueRating: value.valueRating,
                environmentRating: value.environmentRating,
                serviceRating: value.serviceRating,
                valueTags: value.valueTags,
                environmentTags: value.environmentTags,
                serviceTags: value.serviceTags,
                noiseLevel: value.noiseLevel,
                diningDuration: value.diningDuration,
                portionLevel: value.portionLevel,
                transportConvenience: value.transportConvenience,
                specialNotes: value.specialNotes,
                companionSourceIDs: mappedCompanionIDs,
                recommendationSourceID: mappedRecommendationID,
                recommendationSourceType: value.recommendationSourceType,
                recommendationSourceText: value.recommendationSourceText,
                note: value.note,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            )
            if let sameID = byRemoteID[value.sourceID]?.first {
                if Self.visitFingerprint(mapped) == Self.visitFingerprint(sameID.value) {
                    actions.append(action(.visit, value.sourceID, sameID.localID.uuidString.lowercased(),
                                          sameID.localID.uuidString.lowercased(), .exactDuplicate,
                                          "exactStableIDAndContent", "到访记录", [value.sourceRestaurantID]))
                } else {
                    let reviewID = "visit:\(value.sourceID):idCollision"
                    let newID = Self.targetID(sourceHash, .visit, "collision:\(value.sourceID)")
                    if let decision = decisionIndex[reviewID] {
                        guard decision.sourceID == value.sourceID else { throw BackupImportPlanningError.invalidDecision }
                        if decision.selectedOptionID == "create" {
                            guard decision.targetID == newID else { throw BackupImportPlanningError.invalidDecision }
                            actions.append(action(.visit, value.sourceID, newID, sameID.localID.uuidString.lowercased(),
                                                  .create, "userConfirmedNewAfterIDCollision", "到访记录", [value.sourceRestaurantID]))
                        } else if decision.selectedOptionID == "skip" {
                            guard decision.targetID == nil else { throw BackupImportPlanningError.invalidDecision }
                            actions.append(action(.visit, value.sourceID, nil, sameID.localID.uuidString.lowercased(),
                                                  .skip, "userSkippedIDCollision", "到访记录", [value.sourceRestaurantID]))
                        } else { throw BackupImportPlanningError.invalidDecision }
                    } else {
                        actions.append(action(.visit, value.sourceID, newID, sameID.localID.uuidString.lowercased(),
                                              .userReviewRequired, "IDCollision", "到访记录", [value.sourceRestaurantID]))
                        reviews.append(ImportPlanReviewItem(
                            id: reviewID,
                            entityType: .visit,
                            sourceID: value.sourceID,
                            title: "到访 ID 冲突",
                            sourceSafeLabel: Self.visitLabel(value),
                            candidateSafeLabel: Self.visitLabel(sameID.value),
                            reason: "相同稳定 ID 的本地到访内容不同，绝不会覆盖本地记录。",
                            detail: nil,
                            options: [
                                BackupImportReviewOption(id: "create", kind: .create, title: "作为新的到访导入", targetID: newID),
                                BackupImportReviewOption(id: "skip", kind: .skip, title: "跳过", targetID: nil),
                            ],
                            recommendedOptionID: "create"
                        ))
                    }
                }
            } else if let duplicate = fingerprintIndex[Self.visitFingerprint(mapped)]?.first {
                actions.append(action(.visit, value.sourceID, duplicate.localID.uuidString.lowercased(),
                                      duplicate.localID.uuidString.lowercased(), .exactDuplicate,
                                      "canonicalFullContentFingerprint", "到访记录", [value.sourceRestaurantID]))
            } else {
                actions.append(action(.visit, value.sourceID, deterministicTargetID, nil,
                                      .create, "distinctVisit", "到访记录", [value.sourceRestaurantID]))
            }
        }
        return (actions, reviews)
    }

    private func planDishes(
        source: [BackupImportSourceDish],
        local: [BackupImportLocalRecord<BackupImportSourceDish>],
        localRestaurants: [BackupImportLocalRecord<BackupImportSourceRestaurant>],
        localVisits: [BackupImportLocalRecord<BackupImportSourceVisit>],
        restaurantActions: [String: BackupImportPlannedAction],
        visitActions: [String: BackupImportPlannedAction],
        sourceHash: String,
        localRevision: String,
        decisionIndex: [String: BackupImportReviewDecision]
    ) throws -> (actions: [BackupImportPlannedAction], reviews: [ImportPlanReviewItem]) {
        let restaurantRemoteByLocalID = Dictionary(uniqueKeysWithValues: localRestaurants.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        let visitRemoteByLocalID = Dictionary(uniqueKeysWithValues: localVisits.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        let active = local.filter { $0.deletedAt == nil }
        let deletedIDs = Set(local.filter { $0.deletedAt != nil }.map(\.remoteID))
        let byRemoteID = Dictionary(grouping: active, by: \.remoteID)
        let nameIndex = Dictionary(grouping: active) {
            "\($0.value.sourceRestaurantID)|\(Self.normalized($0.value.name))"
        }
        var actions: [BackupImportPlannedAction] = []
        var reviews: [ImportPlanReviewItem] = []
        for value in source.sorted(by: { $0.sourceID < $1.sourceID }) {
            let deterministicTargetID = Self.targetID(sourceHash, .dish, value.sourceID)
            guard let restaurantAction = restaurantActions[value.sourceRestaurantID],
                  let visitAction = visitActions[value.sourceVisitID] else {
                actions.append(action(.dish, value.sourceID, nil, nil, .blocked,
                                      "missingDependencyPlan", value.name, [value.sourceRestaurantID, value.sourceVisitID]))
                continue
            }
            if restaurantAction.action == .skip || visitAction.action == .skip {
                actions.append(action(.dish, value.sourceID, nil, nil, .skip,
                                      "dependencySkipped", value.name, [value.sourceRestaurantID, value.sourceVisitID]))
                continue
            }
            guard ![.blocked, .userReviewRequired].contains(restaurantAction.action),
                  ![.blocked, .userReviewRequired].contains(visitAction.action),
                  let restaurantTargetID = restaurantAction.targetID else {
                actions.append(action(.dish, value.sourceID, nil, nil, .blocked,
                                      "dependencyReviewPending", value.name, [value.sourceRestaurantID, value.sourceVisitID]))
                continue
            }
            if deletedIDs.contains(value.sourceID) || deletedIDs.contains(deterministicTargetID) {
                actions.append(action(.dish, value.sourceID, nil, nil, .skip,
                                      "skipBecauseTombstoned", value.name, [value.sourceRestaurantID, value.sourceVisitID]))
                continue
            }
            if let imported = byRemoteID[deterministicTargetID]?.first {
                actions.append(action(.dish, value.sourceID, imported.localID.uuidString.lowercased(),
                                      imported.localID.uuidString.lowercased(), .exactDuplicate,
                                      "sameImportSourceEntity", value.name,
                                      [value.sourceRestaurantID, value.sourceVisitID]))
                continue
            }
            let restaurantRemoteID = restaurantRemoteByLocalID[restaurantTargetID] ?? restaurantTargetID
            let visitRemoteID = visitAction.targetID.map { visitRemoteByLocalID[$0] ?? $0 } ?? value.sourceVisitID
            if let sameID = byRemoteID[value.sourceID]?.first,
               Self.dishFingerprint(value, mappedRestaurant: restaurantRemoteID, mappedVisit: visitRemoteID)
                == Self.dishFingerprint(
                    sameID.value,
                    mappedRestaurant: sameID.value.sourceRestaurantID,
                    mappedVisit: sameID.value.sourceVisitID
                ) {
                actions.append(action(.dish, value.sourceID, sameID.localID.uuidString.lowercased(),
                                      sameID.localID.uuidString.lowercased(), .exactDuplicate,
                                      "exactStableID", value.name, [value.sourceRestaurantID, value.sourceVisitID]))
                continue
            }
            let candidates = nameIndex["\(restaurantRemoteID)|\(Self.normalized(value.name))"] ?? []
            if let duplicate = candidates.first(where: {
                Self.dishFingerprint(value, mappedRestaurant: restaurantRemoteID, mappedVisit: visitRemoteID)
                    == Self.dishFingerprint(
                        $0.value,
                        mappedRestaurant: $0.value.sourceRestaurantID,
                        mappedVisit: $0.value.sourceVisitID
                    )
            }) {
                actions.append(action(.dish, value.sourceID, duplicate.localID.uuidString.lowercased(),
                                      duplicate.localID.uuidString.lowercased(), .exactDuplicate,
                                      "canonicalFullContentFingerprint", value.name,
                                      [value.sourceRestaurantID, value.sourceVisitID]))
                continue
            }
            if let candidate = candidates.first {
                let reviewID = "dish:\(value.sourceID):sameName"
                let newID = Self.targetID(sourceHash, .dish, value.sourceID)
                if let decision = decisionIndex[reviewID] {
                    guard decision.sourceID == value.sourceID else { throw BackupImportPlanningError.invalidDecision }
                    if decision.selectedOptionID == "create" {
                        guard decision.targetID == newID else { throw BackupImportPlanningError.invalidDecision }
                        actions.append(action(.dish, value.sourceID, newID, candidate.localID.uuidString.lowercased(),
                                              .create, "userConfirmedDistinctDish", value.name,
                                              [value.sourceRestaurantID, value.sourceVisitID]))
                    } else if decision.selectedOptionID == "merge" {
                        guard decision.targetID == candidate.localID.uuidString.lowercased() else { throw BackupImportPlanningError.invalidDecision }
                        actions.append(action(.dish, value.sourceID, candidate.localID.uuidString.lowercased(),
                                              candidate.localID.uuidString.lowercased(), .exactMerge,
                                              "userConfirmedDishMerge", value.name,
                                              [value.sourceRestaurantID, value.sourceVisitID]))
                    } else if decision.selectedOptionID == "skip" {
                        guard decision.targetID == nil else { throw BackupImportPlanningError.invalidDecision }
                        actions.append(action(.dish, value.sourceID, nil, nil, .skip,
                                              "userSkipped", value.name, [value.sourceRestaurantID, value.sourceVisitID]))
                    } else { throw BackupImportPlanningError.invalidDecision }
                } else {
                    actions.append(action(.dish, value.sourceID, newID, candidate.localID.uuidString.lowercased(),
                                          .userReviewRequired, "sameNameSameRestaurant", value.name,
                                          [value.sourceRestaurantID, value.sourceVisitID]))
                    reviews.append(ImportPlanReviewItem(
                        id: reviewID,
                        entityType: .dish,
                        sourceID: value.sourceID,
                        title: "同店同名菜品",
                        sourceSafeLabel: value.name,
                        candidateSafeLabel: candidate.value.name,
                        reason: "同一家餐厅存在同名菜品，但菜名本身不足以证明是同一条记录。",
                        detail: nil,
                        options: [
                            BackupImportReviewOption(id: "create", kind: .create, title: "作为新菜品导入", targetID: newID),
                            BackupImportReviewOption(id: "merge", kind: .merge, title: "与现有菜品合并", targetID: candidate.localID.uuidString.lowercased()),
                            BackupImportReviewOption(id: "skip", kind: .skip, title: "跳过", targetID: nil),
                        ],
                        recommendedOptionID: "create"
                    ))
                }
            } else {
                actions.append(action(.dish, value.sourceID, deterministicTargetID, nil,
                                      .create, "distinctDish", value.name,
                                      [value.sourceRestaurantID, value.sourceVisitID]))
            }
        }
        return (actions, reviews)
    }

    private func planVisitDishes(
        source: [BackupImportSourceVisitDish],
        local: [BackupImportLocalRecord<BackupImportSourceVisitDish>],
        localVisits: [BackupImportLocalRecord<BackupImportSourceVisit>],
        localDishes: [BackupImportLocalRecord<BackupImportSourceDish>],
        restaurantActions: [String: BackupImportPlannedAction],
        visitActions: [String: BackupImportPlannedAction],
        dishActions: [String: BackupImportPlannedAction],
        sourceHash: String
    ) -> [BackupImportPlannedAction] {
        let active = local.filter { $0.deletedAt == nil }
        let deleted = local.filter { $0.deletedAt != nil }
        let visitRemoteByLocalID = Dictionary(uniqueKeysWithValues: localVisits.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        let dishRemoteByLocalID = Dictionary(uniqueKeysWithValues: localDishes.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        return source.sorted(by: { $0.sourceID < $1.sourceID }).map { value in
            let deterministicTargetID = Self.targetID(sourceHash, .visitDish, value.sourceID)
            if deleted.contains(where: {
                $0.remoteID == value.sourceID || $0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID
            }) {
                return action(.visitDish, value.sourceID, nil, nil, .skip,
                              "skipBecauseTombstoned", "菜品关联",
                              [value.sourceRestaurantID, value.sourceVisitID, value.sourceDishID])
            }
            if let imported = active.first(where: {
                $0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID
            }) {
                return action(.visitDish, value.sourceID, imported.localID.uuidString.lowercased(),
                              imported.localID.uuidString.lowercased(), .exactDuplicate,
                              "sameImportSourceEntity", "菜品关联",
                              [value.sourceRestaurantID, value.sourceVisitID, value.sourceDishID])
            }
            guard let restaurant = restaurantActions[value.sourceRestaurantID],
                  let visit = visitActions[value.sourceVisitID],
                  let dish = dishActions[value.sourceDishID] else {
                return action(.visitDish, value.sourceID, nil, nil, .blocked,
                              "missingDependencyPlan", "菜品关联",
                              [value.sourceRestaurantID, value.sourceVisitID, value.sourceDishID])
            }
            if restaurant.action == .skip || visit.action == .skip || dish.action == .skip {
                return action(.visitDish, value.sourceID, nil, nil, .skip,
                              "dependencySkipped", "菜品关联",
                              [value.sourceRestaurantID, value.sourceVisitID, value.sourceDishID])
            }
            guard let visitTarget = visit.targetID, let dishTarget = dish.targetID,
                  ![restaurant.action, visit.action, dish.action].contains(where: {
                      $0 == .blocked || $0 == .userReviewRequired
                  }) else {
                return action(.visitDish, value.sourceID, nil, nil, .blocked,
                              "dependencyReviewPending", "菜品关联",
                              [value.sourceRestaurantID, value.sourceVisitID, value.sourceDishID])
            }
            let visitRemote = visitRemoteByLocalID[visitTarget] ?? visitTarget
            let dishRemote = dishRemoteByLocalID[dishTarget] ?? dishTarget
            if let duplicate = active.first(where: {
                $0.value.sourceVisitID == visitRemote && $0.value.sourceDishID == dishRemote
            }) {
                return action(.visitDish, value.sourceID, duplicate.localID.uuidString.lowercased(),
                              duplicate.localID.uuidString.lowercased(), .exactDuplicate,
                              "exactVisitDishAssociation", "菜品关联",
                              [value.sourceRestaurantID, value.sourceVisitID, value.sourceDishID])
            }
            return action(.visitDish, value.sourceID, deterministicTargetID, nil,
                          .create, "newVisitDishAssociation", "菜品关联",
                          [value.sourceRestaurantID, value.sourceVisitID, value.sourceDishID])
        }
    }

    private func planCompanions(
        source: [BackupImportSourceCompanion],
        local: [BackupImportLocalRecord<BackupImportSourceCompanion>],
        sourceHash: String
    ) throws -> [BackupImportPlannedAction] {
        let activeIndex = Dictionary(grouping: local.filter { $0.deletedAt == nil }) {
            Self.normalized($0.value.displayName)
        }
        let deletedIDs = Set(local.filter { $0.deletedAt != nil }.map(\.remoteID))
        return source.sorted(by: { $0.sourceID < $1.sourceID }).map { value in
            let deterministicTargetID = Self.targetID(sourceHash, .companion, value.sourceID)
            if deletedIDs.contains(value.sourceID) || deletedIDs.contains(deterministicTargetID) {
                return action(.companion, value.sourceID, nil, nil, .skip,
                              "skipBecauseTombstoned", value.displayName, [])
            }
            if let imported = local.first(where: {
                $0.deletedAt == nil && ($0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID)
            }) {
                return action(.companion, value.sourceID, imported.localID.uuidString.lowercased(),
                              imported.localID.uuidString.lowercased(), .exactDuplicate,
                              "sameImportSourceEntity", value.displayName, [])
            }
            if let match = activeIndex[Self.normalized(value.displayName)]?.first {
                return action(.companion, value.sourceID, match.localID.uuidString.lowercased(),
                              match.localID.uuidString.lowercased(), .exactMerge,
                              "normalizedDisplayName", value.displayName, [])
            }
            return action(.companion, value.sourceID, deterministicTargetID, nil,
                          .create, "newPrivateDirectoryEntry", value.displayName, [])
        }
    }

    private func planRecommendationSources(
        source: [BackupImportSourceRecommendationSource],
        local: [BackupImportLocalRecord<BackupImportSourceRecommendationSource>],
        sourceHash: String
    ) throws -> [BackupImportPlannedAction] {
        let activeIndex = Dictionary(grouping: local.filter { $0.deletedAt == nil }) {
            "\(Self.normalized($0.value.displayName))|\($0.value.sourceType)"
        }
        let deletedIDs = Set(local.filter { $0.deletedAt != nil }.map(\.remoteID))
        return source.sorted(by: { $0.sourceID < $1.sourceID }).map { value in
            let deterministicTargetID = Self.targetID(sourceHash, .recommendationSource, value.sourceID)
            if deletedIDs.contains(value.sourceID) || deletedIDs.contains(deterministicTargetID) {
                return action(.recommendationSource, value.sourceID, nil, nil, .skip,
                              "skipBecauseTombstoned", value.displayName, [])
            }
            if let imported = local.first(where: {
                $0.deletedAt == nil && ($0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID)
            }) {
                return action(.recommendationSource, value.sourceID,
                              imported.localID.uuidString.lowercased(),
                              imported.localID.uuidString.lowercased(), .exactDuplicate,
                              "sameImportSourceEntity", value.displayName, [])
            }
            let key = "\(Self.normalized(value.displayName))|\(value.sourceType)"
            if let match = activeIndex[key]?.first {
                return action(.recommendationSource, value.sourceID, match.localID.uuidString.lowercased(),
                              match.localID.uuidString.lowercased(), .exactMerge,
                              "normalizedNameAndType", value.displayName, [])
            }
            return action(.recommendationSource, value.sourceID,
                          deterministicTargetID, nil,
                          .create, "newRecommendationSource", value.displayName, [])
        }
    }

    private func planProfiles(
        source: [BackupImportSourceProfile],
        local: [BackupImportLocalRecord<BackupImportSourceProfile>],
        sourceHash: String,
        localRevision: String,
        decisionIndex: [String: BackupImportReviewDecision]
    ) throws -> (actions: [BackupImportPlannedAction], reviews: [ImportPlanReviewItem]) {
        guard let sourceProfile = source.sorted(by: { $0.sourceID < $1.sourceID }).first else {
            return ([], [])
        }
        guard let localProfile = local.first(where: { $0.deletedAt == nil }) else {
            return ([action(.profile, sourceProfile.sourceID,
                            Self.targetID(sourceHash, .profile, sourceProfile.sourceID), nil,
                            .create, "noCurrentProfile", "个人资料", [])], [])
        }
        let fields: [(String, String, String)] = [
            ("displayName", localProfile.value.displayName, sourceProfile.displayName),
            ("bio", localProfile.value.bio, sourceProfile.bio),
            ("city", localProfile.value.city, sourceProfile.city),
            ("visibility", localProfile.value.visibility, sourceProfile.visibility),
            ("avatarPresetID", localProfile.value.avatarPresetID, sourceProfile.avatarPresetID),
        ]
        var reviews: [ImportPlanReviewItem] = []
        for (field, current, backup) in fields where !backup.isEmpty && !current.isEmpty && current != backup {
            let reviewID = "profile:\(sourceProfile.sourceID):\(field)"
            if let decision = decisionIndex[reviewID] {
                guard decision.sourceID == sourceProfile.sourceID,
                      ["keepCurrent", "useBackup"].contains(decision.selectedOptionID),
                      decision.targetID == localProfile.localID.uuidString.lowercased() else {
                    throw BackupImportPlanningError.invalidDecision
                }
            } else {
                reviews.append(ImportPlanReviewItem(
                    id: reviewID,
                    entityType: .profile,
                    sourceID: sourceProfile.sourceID,
                    title: "个人资料字段冲突",
                    sourceSafeLabel: "备份：\(backup)",
                    candidateSafeLabel: "当前：\(current)",
                    reason: "当前非空值不会被备份自动覆盖。",
                    detail: "字段：\(field)",
                    options: [
                        BackupImportReviewOption(id: "keepCurrent", kind: .keepCurrent, title: "保留当前值", targetID: localProfile.localID.uuidString.lowercased()),
                        BackupImportReviewOption(id: "useBackup", kind: .useBackup, title: "使用备份值", targetID: localProfile.localID.uuidString.lowercased()),
                    ],
                    recommendedOptionID: "keepCurrent"
                ))
            }
        }
        let kind: BackupImportPlanActionKind = reviews.isEmpty ? .exactMerge : .userReviewRequired
        return ([action(.profile, sourceProfile.sourceID, localProfile.localID.uuidString.lowercased(),
                        localProfile.localID.uuidString.lowercased(), kind,
                        reviews.isEmpty ? "safeFillOrConfirmedProfileMerge" : "profileConflict",
                        "个人资料", [])], reviews)
    }

    private func planLists(
        source: [BackupImportSourceRestaurantList],
        local: [BackupImportLocalRecord<BackupImportSourceRestaurantList>],
        sourceHash: String,
        localRevision: String,
        decisionIndex: [String: BackupImportReviewDecision]
    ) throws -> (actions: [BackupImportPlannedAction], reviews: [ImportPlanReviewItem]) {
        let activeByID = Dictionary(grouping: local.filter { $0.deletedAt == nil }, by: \.remoteID)
        let deletedIDs = Set(local.filter { $0.deletedAt != nil }.map(\.remoteID))
        var actions: [BackupImportPlannedAction] = []
        var reviews: [ImportPlanReviewItem] = []
        for value in source.sorted(by: { $0.sourceID < $1.sourceID }) {
            let deterministicTargetID = Self.targetID(sourceHash, .restaurantList, value.sourceID)
            if deletedIDs.contains(value.sourceID) || deletedIDs.contains(deterministicTargetID) {
                actions.append(action(.restaurantList, value.sourceID, nil, nil, .skip,
                                      "skipBecauseTombstoned", value.title, []))
            } else if let imported = local.first(where: {
                $0.deletedAt == nil && ($0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID)
            }) {
                actions.append(action(.restaurantList, value.sourceID,
                                      imported.localID.uuidString.lowercased(),
                                      imported.localID.uuidString.lowercased(), .exactDuplicate,
                                      "sameImportSourceEntity", value.title, []))
            } else if let sameID = activeByID[value.sourceID]?.first {
                if Self.listFingerprint(value) == Self.listFingerprint(sameID.value) {
                    actions.append(action(.restaurantList, value.sourceID, sameID.localID.uuidString.lowercased(),
                                          sameID.localID.uuidString.lowercased(), .exactDuplicate,
                                          "exactStableIDAndContent", value.title, []))
                } else {
                    let reviewID = "restaurantList:\(value.sourceID):idCollision"
                    let newID = Self.targetID(sourceHash, .restaurantList, "collision:\(value.sourceID)")
                    if let decision = decisionIndex[reviewID] {
                        guard decision.sourceID == value.sourceID else { throw BackupImportPlanningError.invalidDecision }
                        if decision.selectedOptionID == "create" {
                            guard decision.targetID == newID else { throw BackupImportPlanningError.invalidDecision }
                            actions.append(action(.restaurantList, value.sourceID, newID, nil, .create,
                                                  "userConfirmedNewAfterIDCollision", value.title, []))
                        } else if decision.selectedOptionID == "skip" {
                            guard decision.targetID == nil else { throw BackupImportPlanningError.invalidDecision }
                            actions.append(action(.restaurantList, value.sourceID, nil, nil, .skip,
                                                  "userSkippedIDCollision", value.title, []))
                        } else { throw BackupImportPlanningError.invalidDecision }
                    } else {
                        actions.append(action(.restaurantList, value.sourceID, newID,
                                              sameID.localID.uuidString.lowercased(), .userReviewRequired,
                                              "IDCollision", value.title, []))
                        reviews.append(ImportPlanReviewItem(
                            id: reviewID,
                            entityType: .restaurantList,
                            sourceID: value.sourceID,
                            title: "榜单 ID 冲突",
                            sourceSafeLabel: value.title,
                            candidateSafeLabel: sameID.value.title,
                            reason: "同一稳定 ID 的榜单内容不同，不会覆盖当前榜单。",
                            detail: nil,
                            options: [
                                BackupImportReviewOption(id: "create", kind: .create, title: "作为新榜单导入", targetID: newID),
                                BackupImportReviewOption(id: "skip", kind: .skip, title: "跳过", targetID: nil),
                            ],
                            recommendedOptionID: "create"
                        ))
                    }
                }
            } else {
                // Title is intentionally not an identity; duplicate titles remain legal.
                actions.append(action(.restaurantList, value.sourceID,
                                      deterministicTargetID, nil,
                                      .create, "newListTitleNotIdentity", value.title, []))
            }
        }
        return (actions, reviews)
    }

    private func planListItems(
        source: [BackupImportSourceRestaurantListItem],
        local: [BackupImportLocalRecord<BackupImportSourceRestaurantListItem>],
        localLists: [BackupImportLocalRecord<BackupImportSourceRestaurantList>],
        localRestaurants: [BackupImportLocalRecord<BackupImportSourceRestaurant>],
        listActions: [String: BackupImportPlannedAction],
        restaurantActions: [String: BackupImportPlannedAction],
        sourceHash: String
    ) -> [BackupImportPlannedAction] {
        let active = local.filter { $0.deletedAt == nil }
        let deleted = local.filter { $0.deletedAt != nil }
        let listRemoteByLocalID = Dictionary(uniqueKeysWithValues: localLists.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        let restaurantRemoteByLocalID = Dictionary(uniqueKeysWithValues: localRestaurants.map {
            ($0.localID.uuidString.lowercased(), $0.remoteID)
        })
        return source.sorted {
            ($0.sourceListID, $0.position, $0.sourceID) < ($1.sourceListID, $1.position, $1.sourceID)
        }.map { value in
            let deterministicTargetID = Self.targetID(sourceHash, .restaurantListItem, value.sourceID)
            if deleted.contains(where: {
                $0.remoteID == value.sourceID || $0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID
            }) {
                return action(.restaurantListItem, value.sourceID, nil, nil, .skip,
                              "skipBecauseTombstoned", "榜单条目",
                              [value.sourceListID, value.sourceRestaurantID])
            }
            if let imported = active.first(where: {
                $0.remoteID == deterministicTargetID
                    || $0.localID.uuidString.lowercased() == deterministicTargetID
            }) {
                return action(.restaurantListItem, value.sourceID,
                              imported.localID.uuidString.lowercased(),
                              imported.localID.uuidString.lowercased(), .exactDuplicate,
                              "sameImportSourceEntity", "榜单条目",
                              [value.sourceListID, value.sourceRestaurantID])
            }
            guard let list = listActions[value.sourceListID],
                  let restaurant = restaurantActions[value.sourceRestaurantID] else {
                return action(.restaurantListItem, value.sourceID, nil, nil, .blocked,
                              "missingDependencyPlan", "榜单条目", [value.sourceListID, value.sourceRestaurantID])
            }
            if list.action == .skip || restaurant.action == .skip {
                return action(.restaurantListItem, value.sourceID, nil, nil, .skip,
                              "dependencySkipped", "榜单条目", [value.sourceListID, value.sourceRestaurantID])
            }
            guard let listTarget = list.targetID, let restaurantTarget = restaurant.targetID,
                  ![list.action, restaurant.action].contains(where: {
                      $0 == .blocked || $0 == .userReviewRequired
                  }) else {
                return action(.restaurantListItem, value.sourceID, nil, nil, .blocked,
                              "dependencyReviewPending", "榜单条目", [value.sourceListID, value.sourceRestaurantID])
            }
            let listRemote = listRemoteByLocalID[listTarget] ?? listTarget
            let restaurantRemote = restaurantRemoteByLocalID[restaurantTarget] ?? restaurantTarget
            if let duplicate = active.first(where: {
                $0.value.sourceListID == listRemote
                    && $0.value.sourceRestaurantID == restaurantRemote
                    && $0.value.position == value.position
                    && $0.value.note == value.note
            }) {
                return action(.restaurantListItem, value.sourceID, duplicate.localID.uuidString.lowercased(),
                              duplicate.localID.uuidString.lowercased(), .exactDuplicate,
                              "exactListItem", "榜单条目", [value.sourceListID, value.sourceRestaurantID])
            }
            return action(.restaurantListItem, value.sourceID,
                          deterministicTargetID, nil,
                          .create, "newListItem", "榜单条目", [value.sourceListID, value.sourceRestaurantID])
        }
    }

    private func action(
        _ type: BackupImportEntityKind,
        _ sourceID: String,
        _ targetID: String?,
        _ matchedLocalID: String?,
        _ action: BackupImportPlanActionKind,
        _ reason: String,
        _ label: String,
        _ dependencies: [String]
    ) -> BackupImportPlannedAction {
        BackupImportPlannedAction(
            entityType: type,
            sourceID: sourceID,
            targetID: targetID,
            matchedLocalID: matchedLocalID,
            action: action,
            reasonCode: reason,
            safeLabel: label,
            dependencySourceIDs: dependencies.sorted()
        )
    }

    private static func actionSort(_ lhs: BackupImportPlannedAction, _ rhs: BackupImportPlannedAction) -> Bool {
        let left = BackupImportEntityKind.allCases.firstIndex(of: lhs.entityType) ?? 0
        let right = BackupImportEntityKind.allCases.firstIndex(of: rhs.entityType) ?? 0
        return left == right ? lhs.sourceID < rhs.sourceID : left < right
    }

    static func targetID(_ sourceHash: String, _ type: BackupImportEntityKind, _ sourceID: String) -> String {
        deterministicUUID("target|\(sourceHash)|\(type.rawValue)|\(sourceID)").uuidString.lowercased()
    }

    static func deterministicUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))")!
    }

    private static func authoritativeProvider(_ value: String) -> Bool {
        value == BackupPlaceProviderV1.appleMaps.rawValue || value == BackupPlaceProviderV1.amap.rawValue
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func restaurantLabel(_ value: BackupImportSourceRestaurant) -> String {
        [value.name, value.city, value.address].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func visitLabel(_ value: BackupImportSourceVisit) -> String {
        "\(value.visitedAt.formatted(date: .numeric, time: .shortened)) · \(value.rating.map { "\($0) 星" } ?? "未评分")"
    }

    private static func distanceMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let deltaP = (lat2 - lat1) * .pi / 180
        let deltaL = (lon2 - lon1) * .pi / 180
        let a = sin(deltaP / 2) * sin(deltaP / 2)
            + cos(p1) * cos(p2) * sin(deltaL / 2) * sin(deltaL / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func visitFingerprint(_ value: BackupImportSourceVisit) -> String {
        fingerprint(FingerprintVisit(value: value))
    }

    private static func dishFingerprint(
        _ value: BackupImportSourceDish,
        mappedRestaurant: String,
        mappedVisit: String
    ) -> String {
        fingerprint(FingerprintDish(
            value: value,
            mappedRestaurant: mappedRestaurant,
            mappedVisit: mappedVisit
        ))
    }

    private static func listFingerprint(_ value: BackupImportSourceRestaurantList) -> String {
        fingerprint(value)
    }

    private static func fingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func seconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}

private nonisolated struct FingerprintVisit: Encodable {
    let restaurant: String
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
    let companions: [String]
    let recommendationSourceID: String?
    let recommendationSourceType: String?
    let recommendationSourceText: String?
    let note: String?

    init(value: BackupImportSourceVisit) {
        restaurant = value.sourceRestaurantID
        visitedAt = value.visitedAt
        diningMode = value.diningMode
        visibility = value.visibility
        partySize = value.partySize
        totalPrice = value.totalPrice
        myActualSpend = value.myActualSpend
        paymentMode = value.paymentMode
        pricePerPerson = value.pricePerPerson
        queueDuration = value.queueDuration
        diningOccasions = value.diningOccasions.sorted()
        diningOccasionText = value.diningOccasionText
        rating = value.rating
        valueRating = value.valueRating
        environmentRating = value.environmentRating
        serviceRating = value.serviceRating
        valueTags = value.valueTags.sorted()
        environmentTags = value.environmentTags.sorted()
        serviceTags = value.serviceTags.sorted()
        noiseLevel = value.noiseLevel
        diningDuration = value.diningDuration
        portionLevel = value.portionLevel
        transportConvenience = value.transportConvenience
        specialNotes = value.specialNotes
        companions = value.companionSourceIDs.sorted()
        recommendationSourceID = value.recommendationSourceID
        recommendationSourceType = value.recommendationSourceType
        recommendationSourceText = value.recommendationSourceText
        note = value.note
    }
}

private nonisolated struct FingerprintDish: Encodable {
    let restaurant: String
    let visit: String
    let name: String
    let taste: String
    let rating: Double?
    let price: Decimal?
    let sortOrder: Int

    init(value: BackupImportSourceDish, mappedRestaurant: String, mappedVisit: String) {
        restaurant = mappedRestaurant
        visit = mappedVisit
        name = value.name
        taste = value.taste
        rating = value.rating
        price = value.price
        sortOrder = value.sortOrder
    }
}
