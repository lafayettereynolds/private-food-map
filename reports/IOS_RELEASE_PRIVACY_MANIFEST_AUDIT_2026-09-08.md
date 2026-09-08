# Taste Map iOS Release Privacy Manifest 最终核查

日期：2026-09-08。范围：本地正式 `ios/TasteMap/TasteMap.xcodeproj` 的 TasteMap Release Archive、Share Extension、实际 Swift Package 依赖、嵌入的第三方 SDK。不是历史测试字符串或旧构建目录的推断。

- [x] **Privacy Manifest：已完成（针对本次审核的源码及 Release Archive）。**
- Apple 当前公开的 manifest 格式、Required Reason API、SDK manifest/签名要求已逐项核对；未发现本次范围内剩余 manifest 缺项。
- 本次没有上传 App Store Connect，不能替代 Apple 服务端的最终校验。归档沿用 Apple Development 签名，`get-task-allow=true`；Distribution 签名/导出和 App Store 隐私问卷仍是独立发布项。最终重归档后应再次运行本报告的产物检查命令。

## 实际路径与 Target

主 App 文件：`ios/TasteMap/TasteMap/PrivacyInfo.xcprivacy`。
扩展文件：`ios/TasteMap/TasteMapShareExtension/PrivacyInfo.xcprivacy`。

两者均为磁盘上的真实、有效 plist 文件。主 App 的 `PBXNativeTarget TasteMap` 引用 `PBXFileSystemSynchronizedRootGroup TasteMap`；该同步组没有排除 manifest。扩展同步组只排除 `Info.plist`，没有排除 manifest。Xcode 会自动把同步组中的 manifest 作为资源复制，不要求再手写一条 PBXResourcesBuildPhase 文件记录。重复添加手工资源记录反而可能造成重复复制。

## 本次修改

1. 主 App 增加 `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`：源码与归档二进制均证实 AppStorage/UserDefaults 的真实使用。
2. 补充实际留存的数据类型：PreciseLocation、CoarseLocation、Contacts、ProductInteraction；补充实际用于个性化推荐的数据用途。
3. 更新现有 Swift 权限/manifest 测试及数据映射文档；标明 9 月 1 日报告为历史快照，不能继续引用其中“不使用 UserDefaults/相机”的结论。
4. 新增 `scripts/audit-ios-privacy.py`，必须传入真实 Archive，验证 Target 归属、正式 Bundle ID、4 份 manifest 的实际存在、声明结构/去重、源码与产物一致，以及签名。

未更改 SDK 官方 manifest、SDK 签名或版本；未新增任何系统权限。

## 数据声明与用途

所有下列数据 `Linked=true`、`Tracking=false`。App Functionality 的完整值是 `NSPrivacyCollectedDataTypePurposeAppFunctionality`，Product Personalization 的完整值是 `NSPrivacyCollectedDataTypePurposeProductPersonalization`。

| 类型（完整 Key 后缀） | 真实依据 | 用途 |
|---|---|---|
| Name | Apple 登录/个人资料名字；私人饭搭子/推荐来源名字 | App Functionality |
| EmailAddress | Apple 登录提供的账户邮箱 | App Functionality |
| UserID | 服务器认证账户 ID、内容所有权与个性化查询 | App Functionality + Product Personalization |
| PurchaseHistory | StoreKit 交易权益；用户记录的用餐消费、价格偏好 | App Functionality + Product Personalization |
| PhotosorVideos | 用户选择/拍摄的图片及授权后的同步 | App Functionality |
| OtherUserContent | 评分、备注、菜品、想吃/餐厅记录、食单等 | App Functionality + Product Personalization |
| PreciseLocation | 同步的用户到访日期与餐厅精确坐标，可描述历史到访地点 | App Functionality + Product Personalization |
| CoarseLocation | 用户资料 city、按城市组织的用餐历史与推荐 | App Functionality + Product Personalization |
| Contacts | 已持久化的关注/好友关系和饭搭子链接，即应用内社交关系 | App Functionality + Product Personalization |
| ProductInteraction | 已同步的“不感兴趣”事件和社区点赞 | App Functionality + Product Personalization |

数据流证据：`Models/Remote/ProfileV1Contracts.swift`（city）；`Models/Remote/RestaurantJSONContract.swift`、`SyncV1Contracts.swift` 与 `SyncRecordMapper.swift`（餐厅坐标、用户到访、消费、评分）；`Services/RecommendationPreferenceSync.swift:172` 与 `worker/recommendationPreferencesV1.ts:62`（偏好事件上传/持久化）；`worker/discoveryV1.ts:370`、`:372`、`:548`、`:1106`（社交关系、价格/口味与城市推荐）。

Contacts 是 Apple 数据分类中的“social graph”，不是系统通讯录权限。定位声明来自实际保存的用户地点数据，不因使用 Core Location 而笼统推定后台轨迹收集。用户未去过的餐厅坐标本身只是地点内容；已确认到访并关联时间/用户的记录才是本次精确地点声明依据。

未添加 IDFA/设备 ID、广告/跟踪、完整照片库、麦克风、Bluetooth、健康、磁盘容量、开机时间等无证据声明。Transient GPS/查询值仅为实时请求服务的部分，不推定为另一个持久化数据流。仅有服务器错误类型日志，也不足以推定客户端 crash/performance SDK 采集；Cloudflare 管理台日志保留配置未在本次访问或更改。

## Required Reason API

| 范围 | 实际 API / 用途 | reason / 结论 |
|---|---|---|
| 主 App | 备份/海报清理读取 app 自有文件的 creation/modification date | FileTimestamp / C617.1，保留，符合容器内文件元数据用途 |
| 主 App | `@AppStorage` 最后搜索城市、UserDefaults 地图提示/转盘日期/账号推荐偏好 | UserDefaults / CA92.1，已补齐，仅 App 自身 defaults 域 |
| 主 App | 用户选择的备份文件 `.fileSizeKey`，用于大小限制/预览 | 该具体 Key 不在 Apple 当前 RRA 列表，不因文档选择器额外添加 3B52.1 |
| 主 App | `.fileSizeKey` 统计 app 自有文件大小 | 不是磁盘剩余容量 API，不添加 DiskSpace |
| 正式 Share Extension | App Group JSON 队列、记录中自身生成的 createdAt/expiresAt | 不读系统文件时间戳/共享 UserDefaults；API 数组为空 |
| 第一方 TasteMapHybridBridge Package | 23 个明确列出的源码文件，业务模型/桥接/内存数据 | 未发现 RRA；独立内部壳使用，正式 App 不以此 Package 产品链接 |
| Capacitor / Cordova 8.5.1 | 官方 tag 的 116 个 iOS 原生源文件与实际嵌入二进制 | 未发现 RRA 调用；SDK 自带空 API 数组与实际相符 |

主 App + 共享源码扫描 267 个文件，正式扩展 + 共享源码 2 个文件。实际 AppGroup 文件队列不同于未加入正式 Target 的旧 `ios/Shared` / `ios/ShareExtension` 模板；后者的 shared UserDefaults 不能用来给正式 App/扩展增加 `1C8F.1`。UITest 中的 systemUptime 不进入 Release App，不能据此增加 boot-time reason。普通 Date、SwiftData 的业务日期不自动等于文件时间戳 API。

归档二进制核查包括四个 Mach-O 的 undefined symbols、相关 ObjC selector 和动态库依赖；主 App 可见 NSUserDefaults/AppStorage，另外三个组件无新增 RRA 符号。文件时间戳以对应源码及已编译主 Target 输入为依据；优化后的符号扫描本身不能替代源码审计。

## 第三方 SDK / Swift Package

正式 `Package.resolved` 只有 `capacitor-swift-pm` 8.5.1，revision `6afa7424fd2fcd8ca1e577478e8a00af284b7e82`。该包包含 Capacitor 和 Cordova 两个 binary targets，无传递包依赖。 这里的 8.5.1 根据锁文件、下载地址和官方 tag 确认；两个 framework 内部 CFBundleShortVersionString/CFBundleVersion 实际为 1.0/1，不能仅靠其 Info.plist 推断 SDK 发布版本。Archive 中也恰好是这两个第三方 frameworks，没有额外 Pod/SDK。

两者均在 Apple 指定 SDK 清单上；各自 XCFramework 的设备与模拟器 slice 都自带 PrivacyInfo.xcprivacy。其四个顶层字段均为：Tracking=false；TrackingDomains=[]；CollectedDataTypes=[]；AccessedAPITypes=[]。原始 XCFramework 的签名为 Drifty Co.，Team `9YN2HU59K8`，`codesign --verify` 通过；App 归档重签名也通过。没有修改厂商签名或伪造 SDK manifest。

独立 `CapApp-SPM` 只引用这两个产品及第一方 `TasteMapHybridBridge`；后者没有第三方依赖。根 Package 的 manifest exclude 不影响正式 App：正式 Target 直接编译同步目录，并且 Archive 根部实际有 manifest。

Cloudflare Workers / D1 / R2 是 HTTPS 后端，不是 iOS SDK，不需要在 App 内伪造 Cloudflare SDK manifest。Apple MapKit/CoreLocation/Photos/SwiftData/StoreKit 等系统框架也不当作第三方 SDK 自行补 manifest。

四份 manifest 分属四个 bundle，是必要的组件级声明，不是同一 bundle 的重复文件。每份内部没有重复 category/data entry。

## Release Archive 实证

Archive：`/Users/lafayette/Projects/private-food-map-hybrid-final-integration/build/privacy-release-audit/TasteMap-Release.xcarchive`

| 归档内相对 App 路径 | SHA-256 |
|---|---|
| `PrivacyInfo.xcprivacy` | `48b32328bf8572888b108fd9365ac257d2287b8c1e1f985047a3bd6464653a4c` |
| `PlugIns/TasteMapShareExtension.appex/PrivacyInfo.xcprivacy` | `521eb6ef8430773e5c010e1838fe9dd8fa5d62b7b76d1cea8d7d8daadcb144e2` |
| `Frameworks/Capacitor.framework/PrivacyInfo.xcprivacy` | `1bac827f49b2b8a5358491b9698203bf191791a6f1ba3a3ace3b1285d52d2d17` |
| `Frameworks/Cordova.framework/PrivacyInfo.xcprivacy` | `5a9b8fc0cddb10201bb47cc2804b3f004c7251476622d25bfc4eb54ed46e1084` |

验证结果：

- `xcodebuild archive ... -scheme TasteMap -configuration Release -destination generic/platform=iOS`：ARCHIVE SUCCEEDED。
- `Task13PrivacySecurityReleaseTests`：4/4 PASS；结果 `build/privacy-release-audit/PrivacyTests.xcresult`。
- `python3 scripts/audit-ios-privacy.py build/privacy-release-audit/TasteMap-Release.xcarchive`：PASS。
- `plutil -lint`：主 App/扩展 manifest 均通过。
- `hybrid:stage:formal`、`hybrid:verify:formal-stage -- <archived app>`：26 个正式 Web 资源字节一致。
- `hybrid:scan:formal-release -- <archived app>`：54 个 App 文件的 Release purity scan PASS。
- 主 App + 扩展 + SDK 归档签名 deep/strict 校验 PASS。

证据目录：`build/privacy-release-audit/`，包括 `archive.log`、`tests.log`、`archive-privacy-verification.json`、`archive-binary-scan.json`、`first-party-api-scan.json`、`capacitor-source-scan.json`、`sdk-signatures.txt` 和资源/purity 验证日志。

## Apple 当前依据

- [Adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [Required Reason API 分类和当前 API 列表](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Approved reason codes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
- [第三方 SDK manifest 与签名要求](https://developer.apple.com/support/third-party-SDK-requirements/)
- [数据类别、个性化用途、社交关系和仅实时处理的数据定义](https://developer.apple.com/app-store/app-privacy-details/)
- [Capacitor 官方 8.5.1 源码](https://github.com/ionic-team/capacitor/tree/8.5.1)

## 当前主 App manifest 完整原文

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>C617.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeName</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeEmailAddress</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
				<string>NSPrivacyCollectedDataTypePurposeProductPersonalization</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePurchaseHistory</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
				<string>NSPrivacyCollectedDataTypePurposeProductPersonalization</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePhotosorVideos</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
				<string>NSPrivacyCollectedDataTypePurposeProductPersonalization</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePreciseLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
				<string>NSPrivacyCollectedDataTypePurposeProductPersonalization</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeCoarseLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
				<string>NSPrivacyCollectedDataTypePurposeProductPersonalization</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeContacts</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
				<string>NSPrivacyCollectedDataTypePurposeProductPersonalization</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeProductInteraction</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
				<string>NSPrivacyCollectedDataTypePurposeProductPersonalization</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

## 当前正式 Share Extension manifest 完整原文

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array/>
</dict>
</plist>
```
