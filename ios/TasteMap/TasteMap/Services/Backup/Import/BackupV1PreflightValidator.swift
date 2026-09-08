import Foundation

nonisolated struct BackupV1PreflightValidator {
    func validate(
        sourceFile: BackupImportSourceFile,
        root: [String: Any],
        envelope: BackupEnvelopeV1,
        inspectedAt: Date
    ) throws -> ImportPreflightResult {
        var issues = BackupV1ShapeValidator().validate(root)
        let entities = envelope.entities
        let actualCounts = BackupImportEntityCounts(
            restaurants: entities.restaurants.count,
            visits: entities.visits.count,
            dishes: entities.dishes.count,
            visitDishes: entities.visitDishes.count,
            photos: entities.photos.count,
            companions: entities.companions.count,
            recommendationSources: entities.recommendationSources.count,
            profiles: entities.profiles.count,
            restaurantLists: entities.restaurantLists.count,
            restaurantListItems: entities.restaurantListItems.count,
            tombstones: normalizedTombstoneCount(envelope.tombstones)
        )

        issues += validateIntegrity(envelope, root: root)
        issues += validateMetadataCounts(envelope)
        issues += validateRelationships(envelope)
        issues += validateTombstones(envelope)
        issues.append(BackupImportIssue(
            severity: .info,
            category: .photoBinary,
            code: "backup_v1_photo_binaries_absent",
            title: "照片原图不在此文件中",
            explanation: "Backup v1 只包含安全照片元数据，不包含照片原图。",
            entityType: "photo",
            count: max(1, entities.photos.count)
        ))

        let relationshipCount = entities.visits.count
            + entities.dishes.count * 2
            + entities.visitDishes.count * 3
            + entities.photos.count
            + entities.visits.reduce(0) { $0 + $1.companionIds.count }
            + entities.visits.filter { $0.recommendationSourceId != nil }.count
            + entities.restaurantListItems.count * 2
        return ImportPreflightResult(
            sourceFormat: .backupV1,
            sourceVersion: BackupV1Contract.schemaVersion,
            fileName: sourceFile.fileName,
            fileSize: sourceFile.fileSize,
            sourceFileSHA256: sourceFile.sourceFileSHA256,
            backupIntegritySHA256: envelope.integrity.digest,
            inspectedAt: inspectedAt,
            sourceMetadata: BackupImportSourceMetadata(
                exportedAt: envelope.exportedAt.rawValue,
                sourceApp: "Taste Map",
                sourceEnvironment: envelope.source.environment.rawValue,
                sourceDatabase: nil
            ),
            counts: actualCounts,
            securityDiscardCount: 0,
            deprecatedFieldCount: 0,
            unsupportedCount: issues.filter { $0.category == .unsupportedData }.reduce(0) {
                $0 + $1.count
            },
            photoBinaryStatus: .metadataOnlyBackupV1,
            issues: issues,
            graphSummary: BackupImportGraphSummary(
                totalEntities: actualCounts.total,
                relationshipCount: relationshipCount,
                providerIdentityCount: entities.restaurants.reduce(0) {
                    $0 + $1.placeIdentities.count
                },
                normalizedTombstoneCount: actualCounts.tombstones
            )
        )
    }

    private func validateIntegrity(_ envelope: BackupEnvelopeV1, root: [String: Any]) -> [BackupImportIssue] {
        do {
            // Hash the supplied payload, not a re-encoded DTO which can insert
            // optional keys (e.g. websiteUrl:null) absent from older v1 files.
            // Shape/type validation remains independent and fail-closed.
            var payload = root
            payload.removeValue(forKey: "integrity")
            let canonical = try BackupCanonicalJSONV1.canonicalString(
                forJSONObject: payload
            )
            let actual = BackupCanonicalJSONV1.sha256Hex(of: canonical)
            guard actual == envelope.integrity.digest else {
                return [blocking(
                    code: "backup_integrity_mismatch",
                    category: .integrity,
                    title: "备份完整性不一致",
                    explanation: "文件内容与 Backup v1 SHA-256 不一致，文件可能损坏或被修改。"
                )]
            }
            return []
        } catch {
            return [blocking(
                code: "backup_integrity_unreadable",
                category: .integrity,
                title: "无法验证备份完整性",
                explanation: "Backup v1 canonical payload 无法完成 SHA-256 验证。"
            )]
        }
    }

    private func validateMetadataCounts(_ envelope: BackupEnvelopeV1) -> [BackupImportIssue] {
        let expected = envelope.metadata.entityCounts
        let actual: [(String, Int, Int)] = [
            ("restaurants", expected.restaurants, envelope.entities.restaurants.count),
            ("visits", expected.visits, envelope.entities.visits.count),
            ("dishes", expected.dishes, envelope.entities.dishes.count),
            ("visitDishes", expected.visitDishes, envelope.entities.visitDishes.count),
            ("photos", expected.photos, envelope.entities.photos.count),
            ("companions", expected.companions, envelope.entities.companions.count),
            ("recommendationSources", expected.recommendationSources, envelope.entities.recommendationSources.count),
            ("profiles", expected.profiles, envelope.entities.profiles.count),
            ("restaurantLists", expected.restaurantLists, envelope.entities.restaurantLists.count),
            ("restaurantListItems", expected.restaurantListItems, envelope.entities.restaurantListItems.count),
            ("tombstones", envelope.metadata.tombstoneCount, envelope.tombstones.count),
        ]
        return actual.compactMap { field, declared, decoded in
            guard declared != decoded else { return nil }
            return blocking(
                code: "metadata_count_mismatch",
                category: .metadata,
                title: "记录数量不一致",
                explanation: "metadata 中的 \(field) 数量与实际解析数量不一致。",
                entityType: field,
                field: field
            )
        }
    }

    private func validateRelationships(_ envelope: BackupEnvelopeV1) -> [BackupImportIssue] {
        let entities = envelope.entities
        var issues = [BackupImportIssue]()
        let restaurants = uniqueIDs(entities.restaurants.map(\.id), type: "restaurant", issues: &issues)
        let visits = uniqueMap(entities.visits, id: \.id, type: "visit", issues: &issues)
        let dishes = uniqueMap(entities.dishes, id: \.id, type: "dish", issues: &issues)
        let photos = uniqueMap(entities.photos, id: \.id, type: "photo", issues: &issues)
        let companions = uniqueIDs(entities.companions.map(\.id), type: "companion", issues: &issues)
        let sources = uniqueIDs(
            entities.recommendationSources.map(\.id),
            type: "recommendationSource",
            issues: &issues
        )
        let profiles = uniqueIDs(entities.profiles.map(\.id), type: "profile", issues: &issues)
        let lists = uniqueIDs(entities.restaurantLists.map(\.id), type: "restaurantList", issues: &issues)
        _ = uniqueIDs(entities.visitDishes.map(\.id), type: "visitDish", issues: &issues)
        _ = uniqueIDs(entities.restaurantListItems.map(\.id), type: "restaurantListItem", issues: &issues)

        for restaurant in entities.restaurants {
            if restaurant.placeIdentities.isEmpty == false {
                let primaryCount = restaurant.placeIdentities.filter(\.isPrimary).count
                if primaryCount != 1 {
                    issues.append(blocking(
                        code: "invalid_primary_place_identity",
                        category: .reference,
                        title: "餐厅外部身份不明确",
                        explanation: "存在 provider identity 的餐厅必须且只能有一个 primary identity。",
                        entityType: "restaurant",
                        sourceReference: restaurant.id,
                        field: "placeIdentities"
                    ))
                }
                var identities = Set<String>()
                for identity in restaurant.placeIdentities {
                    let key = "\(identity.provider.rawValue):\(identity.externalId)"
                    if !identities.insert(key).inserted {
                        issues.append(blocking(
                            code: "duplicate_place_identity",
                            category: .reference,
                            title: "餐厅外部身份重复",
                            explanation: "同一餐厅中出现重复的 provider identity。",
                            entityType: "restaurant",
                            sourceReference: restaurant.id,
                            field: "placeIdentities"
                        ))
                    }
                }
            }
            if let markerPhotoID = restaurant.markerPhotoId,
               photos[markerPhotoID] == nil {
                issues.append(orphan(
                    entityType: "restaurant", id: restaurant.id,
                    field: "markerPhotoId", reference: markerPhotoID
                ))
            }
        }
        for visit in entities.visits {
            if !restaurants.contains(visit.restaurantId) {
                issues.append(orphan(
                    entityType: "visit", id: visit.id,
                    field: "restaurantId", reference: visit.restaurantId
                ))
            }
            for companionID in visit.companionIds where !companions.contains(companionID) {
                issues.append(orphan(
                    entityType: "visit", id: visit.id,
                    field: "companionIds", reference: companionID
                ))
            }
            if let sourceID = visit.recommendationSourceId, !sources.contains(sourceID) {
                issues.append(orphan(
                    entityType: "visit", id: visit.id,
                    field: "recommendationSourceId", reference: sourceID
                ))
            }
        }
        for dish in entities.dishes {
            if !restaurants.contains(dish.restaurantId) {
                issues.append(orphan(
                    entityType: "dish", id: dish.id,
                    field: "restaurantId", reference: dish.restaurantId
                ))
            }
            if visits[dish.originVisitId]?.restaurantId != dish.restaurantId {
                issues.append(orphan(
                    entityType: "dish", id: dish.id,
                    field: "originVisitId", reference: dish.originVisitId
                ))
            }
            if let photoID = dish.photoId,
               !photoMatches(
                    photos[photoID], kind: .dish,
                    parentType: .dish, parentID: dish.id
               ) {
                issues.append(orphan(
                    entityType: "dish", id: dish.id,
                    field: "photoId", reference: photoID
                ))
            }
        }
        for association in entities.visitDishes {
            let visit = visits[association.visitId]
            let dish = dishes[association.dishId]
            if visit?.restaurantId != association.restaurantId
                || dish?.restaurantId != association.restaurantId {
                issues.append(orphan(
                    entityType: "visitDish", id: association.id,
                    field: "relationship", reference: nil
                ))
            }
        }
        for photo in entities.photos {
            let parentExists: Bool
            switch photo.parent.entityType {
            case .restaurant: parentExists = restaurants.contains(photo.parent.entityId)
            case .visit: parentExists = visits[photo.parent.entityId] != nil
            case .dish: parentExists = dishes[photo.parent.entityId] != nil
            case .profile: parentExists = profiles.contains(photo.parent.entityId)
            }
            let expectedParent: BackupPhotoParentEntityTypeV1
            switch photo.kind {
            case .restaurantMarker: expectedParent = .restaurant
            case .visit: expectedParent = .visit
            case .dish: expectedParent = .dish
            case .avatar: expectedParent = .profile
            }
            if !parentExists || photo.parent.entityType != expectedParent {
                issues.append(orphan(
                    entityType: "photo", id: photo.id,
                    field: "parent", reference: photo.parent.entityId
                ))
            }
        }
        for profile in entities.profiles {
            if let photoID = profile.avatarPhotoId,
               !photoMatches(
                    photos[photoID], kind: .avatar,
                    parentType: .profile, parentID: profile.id
               ) {
                issues.append(orphan(
                    entityType: "profile", id: profile.id,
                    field: "avatarPhotoId", reference: photoID
                ))
            }
        }
        for list in entities.restaurantLists {
            if let photoID = list.customCoverPhotoId, photos[photoID] == nil {
                issues.append(orphan(
                    entityType: "restaurantList", id: list.id,
                    field: "customCoverPhotoId", reference: photoID
                ))
            }
        }
        for item in entities.restaurantListItems {
            if !lists.contains(item.listId) {
                issues.append(orphan(
                    entityType: "restaurantListItem", id: item.id,
                    field: "listId", reference: item.listId
                ))
            }
            if !restaurants.contains(item.restaurantId)
                || item.restaurant.restaurantId != item.restaurantId {
                issues.append(orphan(
                    entityType: "restaurantListItem", id: item.id,
                    field: "restaurantId", reference: item.restaurantId
                ))
            }
        }
        return issues
    }

    private func validateTombstones(_ envelope: BackupEnvelopeV1) -> [BackupImportIssue] {
        let entities = envelope.entities
        let active = Set(
            entities.restaurants.map { "restaurant:\($0.id)" }
                + entities.visits.map { "visit:\($0.id)" }
                + entities.dishes.map { "dish:\($0.id)" }
                + entities.visitDishes.map { "visitDish:\($0.id)" }
                + entities.photos.map { "photo:\($0.id)" }
                + entities.companions.map { "companion:\($0.id)" }
                + entities.recommendationSources.map { "recommendationSource:\($0.id)" }
                + entities.profiles.map { "profile:\($0.id)" }
                + entities.restaurantLists.map { "restaurantList:\($0.id)" }
                + entities.restaurantListItems.map { "restaurantListItem:\($0.id)" }
        )
        var issues = [BackupImportIssue]()
        var deletedAtByKey = [String: String]()
        for tombstone in envelope.tombstones {
            let key = "\(tombstone.entityType.rawValue):\(tombstone.id)"
            if active.contains(key) {
                issues.append(blocking(
                    code: "active_tombstone_collision",
                    category: .tombstone,
                    title: "记录同时处于有效和删除状态",
                    explanation: "同一个 stable ID 不能同时出现在 active entities 与 tombstones。",
                    entityType: tombstone.entityType.rawValue,
                    sourceReference: tombstone.id,
                    field: "deletedAt"
                ))
            }
            if let previous = deletedAtByKey[key] {
                if previous == tombstone.deletedAt.rawValue {
                    issues.append(BackupImportIssue(
                        severity: .info,
                        category: .tombstone,
                        code: "duplicate_tombstone_deduplicated",
                        title: "重复删除记录已确定性去重",
                        explanation: "完全相同的 tombstone 在 Dry Run 中只计为一个。",
                        entityType: tombstone.entityType.rawValue,
                        sourceReference: tombstone.id
                    ))
                } else {
                    issues.append(blocking(
                        code: "conflicting_tombstone",
                        category: .tombstone,
                        title: "删除时间存在冲突",
                        explanation: "同一个 tombstone ID 出现不同 deletedAt，暂时无法继续。",
                        entityType: tombstone.entityType.rawValue,
                        sourceReference: tombstone.id,
                        field: "deletedAt"
                    ))
                }
            } else {
                deletedAtByKey[key] = tombstone.deletedAt.rawValue
            }
        }
        return issues
    }

    private func normalizedTombstoneCount(_ tombstones: [BackupTombstoneV1]) -> Int {
        Set(tombstones.map { "\($0.entityType.rawValue):\($0.id)" }).count
    }

    private func uniqueIDs(
        _ ids: [String],
        type: String,
        issues: inout [BackupImportIssue]
    ) -> Set<String> {
        var result = Set<String>()
        for id in ids where !result.insert(id).inserted {
            issues.append(blocking(
                code: "duplicate_active_id",
                category: .reference,
                title: "有效记录 ID 重复",
                explanation: "同一实体类型中的 stable ID 必须唯一。",
                entityType: type,
                sourceReference: id,
                field: "id"
            ))
        }
        return result
    }

    private func uniqueMap<Value>(
        _ values: [Value],
        id: KeyPath<Value, String>,
        type: String,
        issues: inout [BackupImportIssue]
    ) -> [String: Value] {
        var result = [String: Value]()
        for value in values {
            let valueID = value[keyPath: id]
            if result[valueID] != nil {
                issues.append(blocking(
                    code: "duplicate_active_id",
                    category: .reference,
                    title: "有效记录 ID 重复",
                    explanation: "同一实体类型中的 stable ID 必须唯一。",
                    entityType: type,
                    sourceReference: valueID,
                    field: "id"
                ))
            } else {
                result[valueID] = value
            }
        }
        return result
    }

    private func photoMatches(
        _ photo: BackupPhotoV1?,
        kind: BackupPhotoKindV1,
        parentType: BackupPhotoParentEntityTypeV1,
        parentID: String
    ) -> Bool {
        photo?.kind == kind
            && photo?.parent.entityType == parentType
            && photo?.parent.entityId == parentID
    }

    private func orphan(
        entityType: String,
        id: String,
        field: String,
        reference: String?
    ) -> BackupImportIssue {
        blocking(
            code: "broken_reference",
            category: .reference,
            title: "发现断开的数据关联",
            explanation: "记录引用的父级或关联记录不存在或类型不匹配。",
            entityType: entityType,
            sourceReference: id,
            field: field
        )
    }

    private func blocking(
        code: String,
        category: BackupImportIssueCategory,
        title: String,
        explanation: String,
        entityType: String? = nil,
        sourceReference: String? = nil,
        field: String? = nil
    ) -> BackupImportIssue {
        BackupImportIssue(
            severity: .blocking,
            category: category,
            code: code,
            title: title,
            explanation: explanation,
            entityType: entityType,
            sourceReference: sourceReference,
            field: field
        )
    }
}

private nonisolated struct BackupV1ShapeValidator {
    private struct Schema {
        let required: Set<String>
        let allowed: Set<String>
        let maximumStringBytes: [String: Int]

        init(_ keys: [String], optionalKeys: [String] = [], maximumStringBytes: [String: Int] = [:]) {
            required = Set(keys)
            allowed = Set(keys).union(optionalKeys)
            self.maximumStringBytes = maximumStringBytes
        }
    }

    func validate(_ root: [String: Any]) -> [BackupImportIssue] {
        var issues = [BackupImportIssue]()
        validateObject(root, schema: Self.root, path: "envelope", issues: &issues)
        validateNestedObject(root["source"], schema: Self.source, path: "source", issues: &issues)
        validateNestedObject(root["scope"], schema: Self.scope, path: "scope", issues: &issues)
        validateNestedObject(root["entities"], schema: Self.entities, path: "entities", issues: &issues)
        validateNestedObject(root["metadata"], schema: Self.metadata, path: "metadata", issues: &issues)
        if let metadata = root["metadata"] as? [String: Any] {
            validateNestedObject(
                metadata["entityCounts"], schema: Self.entityCounts,
                path: "metadata.entityCounts", issues: &issues
            )
        }
        validateNestedObject(root["integrity"], schema: Self.integrity, path: "integrity", issues: &issues)

        guard let entities = root["entities"] as? [String: Any] else { return issues }
        validateArray(entities["restaurants"], schema: Self.restaurant, type: "restaurant", issues: &issues) { object, id, issues in
            self.validateObjectArray(
                object["placeIdentities"], schema: Self.placeIdentity,
                type: "placeIdentity", parentID: id, maximumCount: 16, issues: &issues
            )
            self.validateTagSet(object["tags"], field: "tags", entityType: "restaurant", id: id, issues: &issues)
        }
        validateArray(entities["visits"], schema: Self.visit, type: "visit", issues: &issues) { object, id, issues in
            for field in ["valueTags", "environmentTags", "serviceTags"] {
                self.validateTagSet(object[field], field: field, entityType: "visit", id: id, issues: &issues)
            }
        }
        validateArray(entities["dishes"], schema: Self.dish, type: "dish", issues: &issues)
        validateArray(entities["visitDishes"], schema: Self.visitDish, type: "visitDish", issues: &issues)
        validateArray(entities["photos"], schema: Self.photo, type: "photo", issues: &issues) { object, id, issues in
            self.validateNestedObject(
                object["parent"], schema: Self.photoParent,
                path: "photo[\(id)].parent", issues: &issues
            )
        }
        validateArray(entities["companions"], schema: Self.companion, type: "companion", issues: &issues)
        validateArray(entities["recommendationSources"], schema: Self.recommendationSource, type: "recommendationSource", issues: &issues)
        validateArray(entities["profiles"], schema: Self.profile, type: "profile", issues: &issues)
        validateArray(entities["restaurantLists"], schema: Self.restaurantList, type: "restaurantList", issues: &issues)
        validateArray(entities["restaurantListItems"], schema: Self.restaurantListItem, type: "restaurantListItem", issues: &issues) { object, id, issues in
            self.validateNestedObject(
                object["restaurant"], schema: Self.listPlace,
                path: "restaurantListItem[\(id)].restaurant", issues: &issues
            )
            if let restaurant = object["restaurant"] as? [String: Any] {
                self.validateObjectArray(
                    restaurant["placeIdentities"], schema: Self.listPlaceIdentity,
                    type: "listPlaceIdentity", parentID: id, maximumCount: 16,
                    issues: &issues
                )
            }
        }
        validateArray(root["tombstones"], schema: Self.tombstone, type: "tombstone", issues: &issues)
        return issues
    }

    private func validateArray(
        _ value: Any?,
        schema: Schema,
        type: String,
        issues: inout [BackupImportIssue],
        nested: (([String: Any], String, inout [BackupImportIssue]) -> Void)? = nil
    ) {
        guard let values = value as? [Any] else { return }
        for (index, value) in values.enumerated() {
            guard let object = value as? [String: Any] else {
                issues.append(shapeIssue(
                    code: "schema_record_not_object", title: "记录结构无效",
                    explanation: "\(type) 集合中存在非对象记录。",
                    entityType: type, sourceReference: "index:\(index)", field: nil
                ))
                continue
            }
            let id = safeReference(object["id"]) ?? "index:\(index)"
            validateObject(object, schema: schema, path: "\(type)[\(id)]", issues: &issues)
            nested?(object, id, &issues)
        }
    }

    private func validateObjectArray(
        _ value: Any?,
        schema: Schema,
        type: String,
        parentID: String,
        maximumCount: Int,
        issues: inout [BackupImportIssue]
    ) {
        guard let values = value as? [Any] else { return }
        if values.count > maximumCount {
            issues.append(shapeIssue(
                code: "schema_array_limit", title: "数组数量超过合同上限",
                explanation: "\(type) 最多允许 \(maximumCount) 项。",
                entityType: type, sourceReference: parentID, field: type
            ))
        }
        for (index, value) in values.enumerated() {
            guard let object = value as? [String: Any] else {
                issues.append(shapeIssue(
                    code: "schema_record_not_object", title: "嵌套记录结构无效",
                    explanation: "\(type) 中存在非对象记录。",
                    entityType: type, sourceReference: parentID,
                    field: "index:\(index)"
                ))
                continue
            }
            validateObject(
                object, schema: schema,
                path: "\(type)[\(parentID):\(index)]", issues: &issues
            )
        }
    }

    private func validateNestedObject(
        _ value: Any?,
        schema: Schema,
        path: String,
        issues: inout [BackupImportIssue]
    ) {
        guard let object = value as? [String: Any] else { return }
        validateObject(object, schema: schema, path: path, issues: &issues)
    }

    private func validateObject(
        _ object: [String: Any],
        schema: Schema,
        path: String,
        issues: inout [BackupImportIssue]
    ) {
        for key in schema.required.subtracting(object.keys).sorted() {
            issues.append(shapeIssue(
                code: "schema_required_field_missing", title: "缺少必需字段",
                explanation: "Backup v1 必需字段未提供。",
                entityType: path, sourceReference: nil, field: key
            ))
        }
        for key in Set(object.keys).subtracting(schema.allowed).sorted() {
            issues.append(shapeIssue(
                code: "schema_unknown_field", title: "发现 Backup v1 未知字段",
                explanation: "Backup v1 不允许合同之外的字段。",
                entityType: path, sourceReference: nil, field: key
            ))
        }
        for (field, maximum) in schema.maximumStringBytes {
            guard let string = object[field] as? String, string.utf8.count > maximum else { continue }
            issues.append(shapeIssue(
                code: "schema_string_limit", title: "字段超过合同长度上限",
                explanation: "字段内容超过 Backup v1 的安全限制。",
                entityType: path, sourceReference: safeReference(object["id"]), field: field
            ))
        }
        for (field, value) in object where field.lowercased().contains("url") {
            if field == "websiteUrl", schema.allowed.contains(field) {
                if value is NSNull { continue }
                if let string = value as? String, let url = URLComponents(string: string),
                   ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                   let host = url.host, !host.isEmpty, url.user == nil, url.password == nil { continue }
                issues.append(shapeIssue(
                    code: "schema_website_url_invalid", title: "官网 URL 无效",
                    explanation: "官网必须是无凭据的 HTTP 或 HTTPS URL。",
                    entityType: path, sourceReference: safeReference(object["id"]), field: field
                ))
                continue
            }
            guard let string = value as? String, !string.hasPrefix("https://") else { continue }
            issues.append(shapeIssue(
                code: "schema_https_required", title: "URL 必须使用 HTTPS",
                explanation: "Backup v1 只允许 HTTPS URL metadata；预检不会访问该 URL。",
                entityType: path, sourceReference: safeReference(object["id"]), field: field
            ))
        }
    }

    private func validateTagSet(
        _ value: Any?,
        field: String,
        entityType: String,
        id: String,
        issues: inout [BackupImportIssue]
    ) {
        guard let tags = value as? [Any] else { return }
        if tags.count > 100 {
            issues.append(shapeIssue(
                code: "schema_tag_count", title: "标签数量超过上限",
                explanation: "Backup v1 每组最多允许 100 个标签。",
                entityType: entityType, sourceReference: id, field: field
            ))
        }
        let strings = tags.compactMap { $0 as? String }
        if strings.count != tags.count || strings.contains(where: { $0.isEmpty || $0.utf8.count > 100 }) {
            issues.append(shapeIssue(
                code: "schema_tag_value", title: "标签内容无效",
                explanation: "标签必须是 1–100 bytes 的非空字符串。",
                entityType: entityType, sourceReference: id, field: field
            ))
        }
        if Set(strings).count != strings.count {
            issues.append(shapeIssue(
                code: "schema_duplicate_tag", title: "标签重复",
                explanation: "Backup v1 标签集合不能包含重复值。",
                entityType: entityType, sourceReference: id, field: field
            ))
        }
    }

    private func safeReference(_ value: Any?) -> String? {
        guard let string = value as? String, string.utf8.count <= 128 else { return nil }
        return string
    }

    private func shapeIssue(
        code: String,
        title: String,
        explanation: String,
        entityType: String?,
        sourceReference: String?,
        field: String?
    ) -> BackupImportIssue {
        BackupImportIssue(
            severity: .blocking,
            category: .schema,
            code: code,
            title: title,
            explanation: explanation,
            entityType: entityType,
            sourceReference: sourceReference,
            field: field
        )
    }

    private static let root = Schema([
        "format", "schemaVersion", "exportId", "exportedAt", "source", "scope",
        "entities", "tombstones", "metadata", "integrity",
    ])
    private static let source = Schema(
        ["platform", "appVersion", "appBuild", "environment"],
        maximumStringBytes: ["appVersion": 64, "appBuild": 64]
    )
    private static let scope = Schema(["kind", "includesPhotoBinaries"])
    private static let entities = Schema([
        "restaurants", "visits", "dishes", "visitDishes", "photos", "companions",
        "recommendationSources", "profiles", "restaurantLists", "restaurantListItems",
    ])
    private static let placeIdentity = Schema([
        "provider", "externalId", "isPrimary", "createdAt", "updatedAt",
    ])
    private static let restaurant = Schema(
        [
            "id", "placeIdentities", "name", "address", "city", "latitude", "longitude",
            "status", "preferenceLevel", "overallRating", "foodRating", "environmentRating",
            "serviceRating", "valueRating", "tags", "longTermNote", "pricePerPerson", "phone",
            "openingHours", "markerType", "markerPhotoId", "merchantImageUrl", "markerEmoji",
            "createdAt", "updatedAt",
        ],
        optionalKeys: ["websiteUrl"],
        maximumStringBytes: [
            "name": 200, "address": 1_000, "city": 200, "longTermNote": 20_000,
            "phone": 100, "websiteUrl": 2_048, "openingHours": 2_000, "merchantImageUrl": 2_048,
            "markerEmoji": 32,
        ]
    )
    private static let visit = Schema([
        "id", "restaurantId", "visitedAt", "diningMode", "visibility", "partySize",
        "totalPrice", "myActualSpend", "paymentMode", "pricePerPerson", "queueDuration",
        "diningOccasions", "diningOccasionText", "rating", "valueRating", "environmentRating",
        "serviceRating", "valueTags", "environmentTags", "serviceTags", "noiseLevel",
        "diningDuration", "portionLevel", "transportConvenience", "specialNotes", "companionIds",
        "recommendationSourceId", "recommendationSourceType", "recommendationSourceText",
        "sharedMealReferenceHint", "note", "createdAt", "updatedAt",
    ])
    private static let dish = Schema(
        ["id", "restaurantId", "originVisitId", "name", "taste", "rating", "price", "photoId", "sortOrder", "createdAt", "updatedAt"],
        maximumStringBytes: ["name": 200, "taste": 2_000]
    )
    private static let visitDish = Schema([
        "id", "restaurantId", "visitId", "dishId", "sortOrder", "createdAt", "updatedAt",
    ])
    private static let photoParent = Schema(["entityType", "entityId"])
    private static let photo = Schema(
        ["id", "parent", "kind", "fileName", "mimeType", "byteSize", "width", "height", "sortOrder", "visibility", "contentSha256", "createdAt", "updatedAt"],
        maximumStringBytes: ["fileName": 512, "mimeType": 255, "contentSha256": 64]
    )
    private static let companion = Schema(
        ["id", "displayName", "createdAt", "updatedAt"],
        maximumStringBytes: ["displayName": 100]
    )
    private static let recommendationSource = Schema(
        ["id", "displayName", "sourceType", "createdAt", "updatedAt"],
        maximumStringBytes: ["displayName": 160]
    )
    private static let profile = Schema(
        ["id", "displayName", "bio", "city", "avatarPhotoId", "avatarPresetId", "visibility", "createdAt", "updatedAt"],
        maximumStringBytes: ["displayName": 200, "bio": 160, "city": 30]
    )
    private static let restaurantList = Schema(
        ["id", "title", "description", "visibility", "isRanked", "coverMode", "customCoverPhotoId", "createdAt", "updatedAt"],
        maximumStringBytes: ["title": 60, "description": 240]
    )
    private static let listPlaceIdentity = Schema(["provider", "externalId", "isPrimary"])
    private static let listPlace = Schema(
        ["globalKey", "restaurantId", "placeIdentities", "name", "address", "city", "latitude", "longitude", "markerPhotoId", "merchantImageUrl", "markerEmoji"],
        maximumStringBytes: [
            "name": 200, "address": 1_000, "city": 200,
            "merchantImageUrl": 2_048, "markerEmoji": 32,
        ]
    )
    private static let restaurantListItem = Schema(
        ["id", "listId", "restaurantId", "restaurantGlobalKey", "position", "note", "restaurant", "createdAt", "updatedAt"],
        maximumStringBytes: ["note": 160]
    )
    private static let tombstone = Schema(["entityType", "id", "deletedAt"])
    private static let entityCounts = Schema([
        "restaurants", "visits", "dishes", "visitDishes", "photos", "companions",
        "recommendationSources", "profiles", "restaurantLists", "restaurantListItems",
    ])
    private static let metadata = Schema(["entityCounts", "tombstoneCount"])
    private static let integrity = Schema(["canonicalization", "algorithm", "digest"])
}
