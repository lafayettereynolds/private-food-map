import Foundation

nonisolated struct LegacyV4PreflightAdapter {
    func result(
        sourceFile: BackupImportSourceFile,
        graph: LegacyBackupStagingGraph,
        inspectedAt: Date
    ) -> ImportPreflightResult {
        let report = graph.conversionReport
        let counts = BackupImportEntityCounts(
            restaurants: graph.restaurants.count,
            visits: graph.visits.count,
            dishes: graph.dishes.count,
            visitDishes: graph.visitDishes.count,
            photos: graph.photos.count,
            companions: graph.companions.count,
            recommendationSources: graph.recommendationSources.count,
            profiles: graph.profiles.count,
            restaurantLists: graph.restaurantLists.count,
            restaurantListItems: graph.restaurantListItems.count,
            tombstones: graph.tombstones.count
        )
        let mappedIssues = report.issues.map(mapIssue)
        let securityDiscardCount = report.securityAuthorityFieldsRemoved.reduce(0) {
            $0 + $1.count
        } + report.ignoredSocialData.reduce(0) { $0 + $1.count }
        let deprecatedCount = report.deprecatedFields.reduce(0) { $0 + $1.count }
        let unsupportedCount = report.unsupportedData.reduce(0) { $0 + $1.count }
        let relationships = graph.visits.count
            + graph.dishes.count * 2
            + graph.visitDishes.count * 3
            + graph.photos.count
            + graph.restaurantListItems.count * 2
        return ImportPreflightResult(
            sourceFormat: .legacyWebV4,
            sourceVersion: 4,
            fileName: sourceFile.fileName,
            fileSize: sourceFile.fileSize,
            sourceFileSHA256: sourceFile.sourceFileSHA256,
            backupIntegritySHA256: nil,
            inspectedAt: inspectedAt,
            sourceMetadata: BackupImportSourceMetadata(
                exportedAt: graph.sourceMetadata.exportedAt.rawValue,
                sourceApp: graph.sourceMetadata.app,
                sourceEnvironment: graph.sourceMetadata.environment,
                sourceDatabase: graph.sourceMetadata.databaseName
            ),
            counts: counts,
            securityDiscardCount: securityDiscardCount,
            deprecatedFieldCount: deprecatedCount,
            unsupportedCount: unsupportedCount,
            photoBinaryStatus: .partialLegacyMetadataOnly,
            issues: mappedIssues,
            graphSummary: BackupImportGraphSummary(
                totalEntities: counts.total,
                relationshipCount: relationships,
                providerIdentityCount: graph.restaurants.reduce(0) {
                    $0 + $1.placeIdentities.count
                },
                normalizedTombstoneCount: graph.tombstones.count
            )
        )
    }

    private func mapIssue(_ issue: LegacyBackupIssue) -> BackupImportIssue {
        let severity: BackupImportIssueSeverity = switch issue.severity {
        case .info: .info
        case .warning: .warning
        case .requiresReview: .requiresReview
        case .blocking: .blocking
        }
        let category: BackupImportIssueCategory = switch issue.category {
        case .normalization: .normalization
        case .discardedField: .unsupportedData
        case .deprecatedField: .deprecatedField
        case .securityAuthority: .securityAuthority
        case .unsupportedData: .unsupportedData
        case .brokenReference, .invalidRecord: .reference
        case .ignoredSocialData: .socialAuthority
        case .photoBinary, .inlineBinary: .photoBinary
        case .ambiguousMapping: .normalization
        case .informational: .informational
        }
        let copy = friendlyCopy(for: issue)
        return BackupImportIssue(
            severity: severity,
            category: category,
            code: issue.code.rawValue,
            title: copy.title,
            explanation: copy.explanation,
            entityType: issue.entityType.rawValue,
            sourceReference: issue.sourceRecordID,
            field: issue.field,
            count: issue.count
        )
    }

    private func friendlyCopy(for issue: LegacyBackupIssue) -> (title: String, explanation: String) {
        switch issue.code {
        case .authorityFieldRemoved, .linkedSocialIdentityRemoved:
            ("身份或权限字段已忽略", "这些字段不能证明当前用户身份或数据所有权，不会进入后续计划。")
        case .serverAuthoritativeSocialDataIgnored:
            ("社交权限数据已忽略", "好友、共享关系等服务端权威状态不会从本地备份恢复。")
        case .deprecatedFieldDiscarded:
            ("发现旧版已停用字段", "这些内容会保留在诊断摘要中，但不会重新启用旧版输入能力。")
        case .unknownTopLevelCollectionDiscarded:
            ("发现未知数据集合", "该集合不属于已确认的 Legacy Web v4 数据模型，需要后续人工确认。")
        case .unknownFieldDiscarded:
            ("发现不支持的旧字段", "该字段未进入安全 staging，也不会被自动写入。")
        case .brokenReference, .invalidPhotoParent:
            ("发现断开的数据关联", "记录引用的父级不存在，当前文件暂时无法安全继续。")
        case .invalidRecord, .invalidField:
            ("发现无效旧记录", "旧记录无法按已锁定的 v4 policy 安全规范化。")
        case .multipleProfilesRequireReview:
            ("发现多个旧版 Profile", "不能自动决定哪个 Profile 属于当前用户，需要后续确认。")
        case .providerIdentityCollisionAcrossRestaurants, .conflictingPrimaryProviderIdentity,
             .ambiguousPhotoParent:
            ("存在身份映射歧义", "预检不会自动合并或选择，需要后续数据匹配阶段处理。")
        case .photoBinaryUnavailable, .inlineBinaryDiscarded, .photoTransientStateRemoved:
            ("照片原图不可由此文件恢复", "仅保留安全照片元数据；路径、上传状态或内嵌二进制不会被采用。")
        case .sharedMealReferenceIsNonAuthoritative:
            ("共享用餐引用不是权限证明", "该提示不会重建共享关系或参与者权限。")
        case .legacyFormatDoesNotContainFollows:
            ("旧备份不包含关注关系", "关注关系属于服务端权威数据，不从 Legacy 文件推断。")
        case .deletedRecordReducedToTombstone:
            ("删除记录已转换为 tombstone", "Dry Run 只保留删除事实，不产生任何本地删除操作。")
        case .duplicateProviderIdentityRemoved, .duplicateSourceID,
             .providerNeutralRestaurant:
            ("旧记录已安全规范化", "已按 F1-C1 的确定性规则建立 non-authoritative staging。")
        case .photoProviderLocatorRemoved:
            ("照片 Provider locator 已移除", "外部存储定位信息不具有恢复权限，也不会被访问。")
        }
    }
}
