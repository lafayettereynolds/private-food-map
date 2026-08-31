# Taste Map｜Release Binary Purity Fix 验收报告

日期：2026-08-31  
范围：iOS Release compilation / signed Archive purity  
分支：`fix/release-binary-purity`  
基线：`main@a4739f04a5dd357f525955df7acf67df8937f5e9`

## 1. 结论

本轮 Release Binary Purity Fix 已通过。

- `IsolatedAuthCredentialStore` 不再进入 Release 主 App 或 Share Extension。
- `TestNetworkBlockerURLProtocol` 不再进入 Release 主 App 或 Share Extension。
- `TasteMapTestRuntimeResources` 不再进入 Release 主 App 或 Share Extension。
- Backup Import 的 fixture input、人工延迟、failure injection、Development fixture implementation 不再进入 Release 主 App 或 Share Extension。
- 正式 `AuthCredentialStoring`、真实 Keychain、真实 URLSession、Backup Import 文件读取、preflight、planning、transaction writer 与正式 UI 流程全部保留。
- Debug 下的 unit/UI/Development fixture 能力继续可用，并由 601 项单元/集成测试与 8 条相关 UI 测试验证。
- 签名 Archive 的主 App、Share Extension 与完整 App bundle 对目标 test-only 类型/环境键均为 0 命中。
- F1-C4 精确重复导入 regression 已通过，正式从 Release blocker 关闭；未使用真实用户数据进行第二次破坏性 Import。

## 2. 编译边界

### 正式 abstraction / production implementation（保留 Release）

- `AuthCredentialStoring`
- `KeychainCredentialStore`
- `NativeAuthServices`
- 生产 `URLSession.shared`
- `BackupImportFileReader.read(fileURL:)`
- Backup Import preflight / planning / merge / transaction 正式能力
- Backup Import 正式文件选择和用户确认流程

### test-only concrete implementation（仅 Debug）

- `TasteMapRuntimeTier.unit`
- `TasteMapRuntimeTier.localIntegration`
- `TasteMapRuntimeTier.ui`
- `TasteMapRuntimeTier.developmentE2E`
- `IsolatedAuthCredentialStore`
- `TestNetworkBlockerURLProtocol`
- `TasteMapTestRuntimeResources`
- `BackupImportFixtureInput`
- `BackupImportDevelopmentFixture`
- `BackupImportFailurePoint`
- `BackupImportPlanningError.injectedFailure`
- Backup Import in-memory fixture reader、人工 delay 与 transaction failure injection
- Preview / UI fixture-only state、actions、factories 与 preview declarations

Release 运行时固定为 `.application`；环境变量或 launch argument 无法把 Release 切换到测试 tier。

## 3. 修改文件

### Runtime 与 dependency injection

- `ios/TasteMap/TasteMap/App/TasteMapRuntimeConfiguration.swift`
- `ios/TasteMap/TasteMap/TasteMapApp.swift`

### Backup Import 编译边界

- `ios/TasteMap/TasteMap/Features/Settings/Import/BackupImportDevelopmentFixtures.swift`
- `ios/TasteMap/TasteMap/Features/Settings/Import/BackupImportPreflightView.swift`
- `ios/TasteMap/TasteMap/Features/Settings/TasteMapSettingsView.swift`
- `ios/TasteMap/TasteMap/Services/Backup/Import/BackupImportFileReader.swift`
- `ios/TasteMap/TasteMap/Services/Backup/Import/BackupImportFlowCoordinator.swift`
- `ios/TasteMap/TasteMap/Services/Backup/Import/BackupImportPlanningTypes.swift`
- `ios/TasteMap/TasteMap/Services/Backup/Import/BackupImportTransactionWriter.swift`

### Preview / fixture-only compile boundary

- `ios/TasteMap/TasteMap/Features/Analysis/AnnualRecapAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/DiningCompanionAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/MonthlyRecapAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/RecommendationSourceAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/RecommendationSourcePreviewFixtures.swift`
- `ios/TasteMap/TasteMap/Features/Discovery/DiscoveryPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Roulette/RestaurantRoulettePreviews.swift`
- `ios/TasteMap/TasteMap/Features/Visit/P2BPhotoPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Visit/P2CDishPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Visit/P2DRatingPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Visit/P2EVisitContextPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Visit/P2FCompanionSourcePreviews.swift`
- `ios/TasteMap/TasteMap/Features/Visit/VisitEditorPreviews.swift`

未修改 Xcode project、Bundle ID、Team、Signing、Capabilities、SwiftData schema、Worker、D1、Production、StoreKit 正式配置、UI 布局或 App Icon。

## 4. 测试结果

### 单元 / 集成

完整 `TasteMapTests` 集合按测试宿主内存隔离分成四个串行 shard；测试集合与语义没有删减。

| Shard | Tests | Passed | Failed |
|---|---:|---:|---:|
| 1 | 177 | 177 | 0 |
| 2 | 139 | 139 | 0 |
| 3 | 200 | 200 | 0 |
| 4 | 85 | 85 | 0 |
| 合计 | **601** | **601** | **0** |

对应 xcresult：

- `/tmp/tastemap-purity-shard-1.xcresult`
- `/tmp/tastemap-purity-shard-2.xcresult`
- `/tmp/tastemap-purity-shard-3-retry.xcresult`
- `/tmp/tastemap-purity-shard-4-retry.xcresult`

### 相关 UI tests

以下 8 条全部通过（0 failure）：

1. Settings → Backup Export privacy flow
2. Legacy Import preflight / dry run / details
3. Blocking fixture cannot continue
4. Development matching plan requires final confirmation
5. Backup v1 formal Import completes and shows local result
6. Legacy review create Import and Restaurant navigation
7. Injected transaction failure keeps existing data unchanged
8. Pre-transaction cancel writes nothing

结果：`8/8 PASS`  
xcresult：`/tmp/tastemap-purity-import-ui.xcresult`

## 5. F1-C4 精确 regression

测试：`BackupImportMergeEngineTests/repeatedLegacyManualMergeIsIdempotent`

验证链路：

`Legacy v4 first import`
→ `second identical source`
→ `cross-provider Restaurant candidate`
→ `manual Restaurant merge`
→ `dependent Visit re-resolve`
→ `exactDuplicate`
→ `no second Visit`
→ `no extra mutation`

结果：`PASS`

结论：F1-C4 duplicate Visit 已从 Release blocker 正式关闭。该结论来自确定性自动化 regression；没有对真实用户数据执行第二次 Import。

## 6. Build / Archive

| 验证 | 结果 |
|---|---|
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Generic iOS Device Release build | PASS |
| Signed Release Archive | PASS |
| Archive main App code signature verification | PASS |
| Archive Share Extension code signature verification | PASS |

Archive：`/tmp/tastemap-purity-archive.QHEfIu/TasteMap.xcarchive`

Archive 使用项目现有 Automatic Signing、Team 与 Apple Development provisioning 成功签名；本轮未修改任何签名配置。

## 7. Archive binary / string scan

扫描对象：

- `TasteMap.app/TasteMap`
- `TasteMap.app/PlugIns/TasteMapShareExtension.appex/TasteMapShareExtension`
- 完整 `TasteMap.app` bundle

扫描方式：

1. `strings -a`
2. `nm` + Swift demangle
3. App bundle recursive binary scan

目标模式包括：

- `IsolatedAuthCredentialStore`
- `TestNetworkBlockerURLProtocol`
- `TasteMapTestRuntimeResources`
- `BackupImportFixtureInput`
- `BackupImportFailurePoint`
- `BackupImportDevelopmentFixture(s)`
- `fixtureDelay`
- `injectedFailure`
- `TASTEMAP_TEST_TIER`
- `TASTEMAP_UI_TEST_RUNTIME`
- F1-C2/C3/C4 Import UI-test environment keys

结果：

| 扫描 | Main App | Share Extension / Bundle | 结果 |
|---|---:|---:|---|
| exact strings | 0 | 0 | PASS |
| demangled symbols | 0 | 0 | PASS |
| recursive bundle | — | 0 | PASS |

广义 `preview` 扫描只剩正式产品语义，例如 Public List preview、Account Deletion preview 和 poster preview；这些不是 test fixture 或测试运行时实现。

## 8. 安全边界

- Production Worker：未访问、未部署。
- Production D1：未访问、未 migration、未写入。
- Production R2：未访问、未写入。
- Secret / Product ID：未新增、未输出、未提交。
- App Store Connect：未上传。
- StoreKit 正式配置：未修改。
- App Icon：未修改。
- Product Parity / UI：未修改。

## 9. 最终状态

Release binary purity：**PASS**  
Backup Import 正式能力：**保留并回归通过**  
Debug test fixture 能力：**保留并回归通过**  
F1-C4 duplicate Visit blocker：**CLOSED**
