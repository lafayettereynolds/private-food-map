# Release Capabilities / Entitlements Final Audit

后继说明：本报告的 credential lifecycle 缺口已进入同日后续修复；当前结果见 [Apple credential lifecycle closure](APPLE_CREDENTIAL_LIFECYCLE_CLOSURE_2026-09-08.md)。下文保留原始审计时点，不将历史 FAIL 擦除或冒称当时已通过。其他 capability/线上 Privacy 问卷边界不变。

审计时间：2026-09-08 22:50–23:00 CST。项目：`/Users/lafayette/Projects/private-food-map-hybrid-final-integration`。
HEAD：`4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50`，**dirty integrated workspace，不是该 commit 的 clean 构建**。

范围：本地 Xcode project/settings、Swift/Worker 认证与路由源码、entitlements、Info.plist、Privacy Manifest，以及本轮独立 signed Release device build。未连接 Production D1；未登录 Apple、未部署、未安装/启动手机、未修改 StoreKit 商品/Bundle ID/Team、未 Archive、未上传。

## 结论

| Gate | 结果 | 边界 |
|---|---|---|
| SIGN IN WITH APPLE CONFIG | PASS | 主 App 源码 entitlement、签名 entitlement 与有效 provisioning 一致；扩展未继承 |
| SIGN IN WITH APPLE（包含本次要求的 credential lifecycle） | FAIL | 未实现 Apple credential state / revocation handling；不是普通购买/Restore 回归失败 |
| ASSOCIATED DOMAINS | CONFIG PASS, REAL DEVICE PENDING | 正式 `applinks:tastemap.cn`；本轮不重新请求线上 AASA、不点击手机 |
| SHARE EXTENSION CONFIG | PASS | 实际嵌入、可执行文件、activation rule、签名与 App Group 均通过 |
| SHARE EXTENSION REAL DEVICE | PENDING | 本轮不做真实第三方分享 |
| APP GROUP | REQUIRED / CONFIG PASS | 主 App 与扩展共享待导入 JSON 队列 |
| KEYCHAIN SHARING | NOT REQUIRED / CONFIG NOT APPLICABLE | 使用主 App 默认私有 Keychain；无跨 target access group |
| LOCATION PERMISSIONS | PASS | When In Use；无 Always / background location |
| CAMERA PERMISSIONS | PASS | 用户主动拍照；有 Camera purpose string |
| PHOTOS PERMISSIONS | PASS | PhotosPicker/PHPicker 输入 + 保存海报 add-only；无 full-library read |
| PRIVACY MINIMIZATION | PASS | 未发现多余 UsageDescription/system permission |
| RELEASE TARGET CONSISTENCY | PASS | 正式两个 target ID/Team/version/embedding 对齐；特殊测试配置不进入 Release |
| RELEASE SIGNING CONFIG | PASS | 本轮 Apple Development device 签名与 profiles 匹配；**不是 Distribution export PASS** |
| PRIVACY / CAPABILITY CONSISTENCY | FAIL / EVIDENCE INCOMPLETE | 本地代码/权限/manifest PASS；线上 App Privacy 问卷未核对，不能宣称三方最终 PASS |

NORMAL STOREKIT REAL DEVICE 保留冻结 PASS，不要求再次购买/Restore。此审计不改变 Production baseline、Referral hold 或 Cutover Gate；HYBRID_PRIMARY / FINAL RC 仍 NOT YET。

## 1. 实际 target 与配置清单

`xcodebuild -list -json`：正式 project 有 4 个 target，没有额外 shipping extension。project 内 workspace 仅是该 project 的 workspace，不是第二个产品。

下表 Entitlements / Info.plist 相对于 `ios/TasteMap/`；`generated` 表示 `GENERATE_INFOPLIST_FILE=YES`，不是缺失文件。全部正式项目 target 的 `CODE_SIGN_STYLE=Automatic`，`DEVELOPMENT_TEAM=7G5J9MJX88`。

| Target | Release Bundle ID | Team | Release Entitlements | Release Info.plist | Release Signing | Release / App Store included | Result |
|---|---|---|---|---|---|---|---|
| TasteMap | com.lafayette.tastemap | 7G5J9MJX88 | TasteMap/TasteMapRelease.entitlements | BuildIdentity.plist + generated | Automatic / Apple Development 本轮 | YES / YES（正式 scheme 的 Archive 产品，未上传） | PASS |
| TasteMapShareExtension | com.lafayette.tastemap.ShareExtension | 7G5J9MJX88 | TasteMapShareExtension/TasteMapShareExtension.entitlements | TasteMapShareExtension/Info.plist | Automatic / Apple Development 本轮 | YES / YES（嵌入主 App，不独立上架） | PASS |
| TasteMapTests | com.lafayette.TasteMapTests | 7G5J9MJX88 | 无 | generated | Automatic 配置，未构建进本次 Release | NO / NO | 测试专用 |
| TasteMapUITests | com.lafayette.TasteMapUITests | 7G5J9MJX88 | 无 | generated | Automatic 配置，未构建进本次 Release | NO / NO | 测试专用 |

主 App / Share Extension 配置均为 `Debug, DebugQA, DebugPrivatePreview, Release, ReleaseSandbox`。两个测试 target 为 `Debug, Release, ReleaseSandbox`；未给测试 target 添加生产 capability，未混入正式 Archive。

另一个实际 project：`hybrid/capacitor-shell/ios/App/App.xcodeproj`，target `App`，Debug/Release，Bundle ID `com.lafayette.tastemap.hybrid.internal`，Automatic，Team 未设置，无 entitlement file，Info.plist `App/Info.plist`。这是独立内部 Capacitor 壳，**不参与正式 TasteMap scheme 的 Release / App Store 产品**，没有自动补正式 Team/capability。

历史 `ios/ShareExtension`、`ios/Shared`、`ios/TasteMapApp/*.example` 未加入正式 target。`.qa` App/extension 是明确 DebugQA 配置，不是第二套正式 Bundle ID。正式扩展后缀 `ShareExtension` 大小写在 project、plist、签名、profile 中完全一致；测试 Bundle ID 中的 `TasteMapTests/TasteMapUITests` 大写不是主 App ID 漂移。没有新增或修改任何 ID。

### Debug / Release 差异

| 设置 | Debug | Release | 结论 |
|---|---|---|---|
| 主 App PRODUCT_BUNDLE_IDENTIFIER | com.lafayette.tastemap | 相同 | PASS |
| Extension PRODUCT_BUNDLE_IDENTIFIER | com.lafayette.tastemap.ShareExtension | 相同 | PASS |
| DEVELOPMENT_TEAM / CODE_SIGN_STYLE | 7G5J9MJX88 / Automatic | 相同 | PASS |
| 主 App CODE_SIGN_ENTITLEMENTS | TasteMap/TasteMap.entitlements | TasteMap/TasteMapRelease.entitlements | 有意区分域名，SIWA/App Group 相同 |
| 主 App INFOPLIST_FILE | generated | BuildIdentity.plist + generated | 有意加入构建 identity 输入，未全局覆盖 extension |
| Extension entitlement / plist | 正式 extension 两文件 | 相同 | PASS |
| PRODUCT_NAME | 各自 `$(TARGET_NAME)` | 相同 | PASS |
| MARKETING_VERSION / CURRENT_PROJECT_VERSION | 1.0 / 1 | 相同 | 本轮是审计包，不是唯一真机测试包/候选 RC |
| SWIFT_ACTIVE_COMPILATION_CONDITIONS（含 project） | DEBUG | 空，无 DEBUG/QA/PRIVATE_PREVIEW/SANDBOX | PASS |
| OTHER_CODE_SIGN_FLAGS / explicit provisioning override | 未设置 | 未设置 | Automatic 使用本地有效 profile |
| Associated Domains | applinks:api-dev.tastemap.cn?mode=developer | applinks:tastemap.cn | Debug APIConfiguration 有明确 development 路径；未泄漏 Release |
| 3 个权限 purpose strings | Location When In Use / Camera / Photos Add | 完全相同 | PASS |

DebugQA：`.qa` Bundle ID、`.qa` App Group、QA entitlement、`DEBUG TASTEMAP_QA`。DebugPrivatePreview：正式 ID/group/Release entitlement，但 `TASTEMAP_PRIVATE_PREVIEW`；不是正式 Release。ReleaseSandbox：正式 ID/group/Release entitlement，但 `TASTEMAP_SANDBOX_BUILD`，不作为正式生产候选。

注意：`TasteMap.xcscheme` 的 Run 当前为 DebugPrivatePreview，**Archive/Profile 为 Release**。按 Run 看见的 Hybrid Private 不能当作 Release renderer 证据。本轮显式 `-configuration Release`，没有更改 scheme。Private/QA scheme 不负责正式 Archive；另有明确命名 Sandbox TestFlight scheme 使用 ReleaseSandbox，不能替代正式 TasteMap Release。

## 2. Sign in with Apple：配置通过，生命周期缺口

实际主 App 签名：

```text
application-identifier = 7G5J9MJX88.com.lafayette.tastemap
com.apple.developer.applesignin = [Default]
com.apple.developer.associated-domains = [applinks:tastemap.cn]
com.apple.security.application-groups = [group.com.lafayette.tastemap]
com.apple.developer.team-identifier = 7G5J9MJX88
get-task-allow = true
```

Apple 颁发的 embedded provisioning profile 允许这些 entitlements，签名证书在该 profile 的 DeveloperCertificates 内且 profile 未过期。由此验证 App ID/Team 的本地签名一致性；没有把“未打开 Developer Portal”伪称为 Portal 实时截图检查。Xcode project 的 `SystemCapabilities` 元数据只显式列 IAP；实际 SIWA/Associated Domains/App Groups 来源是已引用 entitlement 文件和 profile，缺少冗余 UI 元数据不是运行时 capability 丢失，不为此无依据修改配置。

源码审计：

- `AppleSignInService.swift`：ASAuthorization callback 成功/错误路径、challenge、hashed nonce、state 比较、identity token UTF-8 校验、backend exchange 均存在。reauthentication 比较 Taste Map userID，错账号会撤销新建 session，不写入 Keychain。
- `worker/authV1.ts`：RS256/JWK signature、issuer、audience、expiry/iat/nbf、subject/nonce、challenge 单次使用、identity token replay 防护；本轮仅运行 mock 数据库自动测试，无远程 D1。
- `AuthSessionManager.swift` / `NativeAuthServices.swift`：Keychain restore、session refresh、401 清除、本地 logout、guest/authenticated user scope 切换存在。检查到这些实现不等于真机账号切换已 PASS。
- 正式 session Keychain service `com.lafayette.tastemap.auth`，account `native-session-v1`；development 使用独立 `.auth.development` service。`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不 iCloud 同步，无 `kSecAttrAccessGroup`。扩展不读取 auth token。
- **缺口**：在正式 iOS/Hybrid/Worker 源码未找到 `getCredentialState`、`credentialRevokedNotification` 或 `consent-revoked` 处理。当前 `AuthCredential` 不保存 Apple `credential.user`，只有 Taste Map userID；不能把它直接传给 Apple credential state API。
- `authorizationCode` 未消费/交换；当前登录是 identity-token verification + Taste Map session，不是 Apple refresh-token/revoke-token 流程。缺 authorization code 不等于当前登录不能工作，但不能声称 Apple 授权撤销生命周期已闭环。

因此 SIWA CONFIG PASS，但用户要求的完整 credential lifecycle 审计 FAIL。补齐需要认证状态/存储/生命周期及回归测试的代码工作，超过本轮列出的 entitlement/permission/target 自动修复范围；没有借审计改写认证协议。普通 Taste Map session revoked/expired 的处理不能替代 Apple 侧授权撤销。

Apple 参考：[credentialRevokedNotification](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/credentialrevokednotification)、[Get the most out of Sign in with Apple](https://developer.apple.com/videos/play/wwdc2020/10173/)。

## 3. Associated Domains / Universal Links

- UNIVERSAL LINK DOMAIN：`tastemap.cn`。
- AASA APP IDENTIFIER：`7G5J9MJX88.com.lafayette.tastemap`，与签名 Team + Bundle ID 完全一致。
- 本地 `worker/index.ts` 的 `/.well-known/apple-app-site-association` response 包含 `/share/*` 和 `/invite/*`；`ProductionEnvironment.json` 提供 appleAppID。
- AASA endpoint 是文件路径，不是需要加入 applinks components 的 App 内容路由。
- 主 App Release 不含 origin-api/api-dev/workers.dev；扩展没有 Associated Domains。
- `RootTabView.swift` 的 onOpenURL/onContinueUserActivity、初始 task/scene active，以及 Hybrid root 对应 handoff 存在。Referral availability=false 时不进行 attribution；后端/映射未删除。
- 普通 public share 使用 `/share/<32字符ID>`，不是任意 `/restaurants` URL。真实 cold/warm link handoff 本轮未测试。
- 按本轮“本地审计、不做 Production D1 联调”边界，未重新请求线上 AASA/CDN。既有上线事实仍是此前证据，本报告只给源码/签名 CONFIG PASS，不声称当前线上缓存重新验收 PASS。

## 4. Share Extension / App Group / Keychain

实际产物 `TasteMap.app/PlugIns/TasteMapShareExtension.appex`，Bundle ID `com.lafayette.tastemap.ShareExtension`，`NSExtensionPointIdentifier=com.apple.share-services`，principal class `TasteMapShareExtension.ShareViewController`。`APPLICATION_EXTENSION_API_ONLY=YES`；`SKIP_INSTALL=YES` 是扩展不独立安装，不代表未嵌入 App。

Activation rule 精确为 text=true、WebURLWithMaxCount=1；没有 TRUEPREDICATE、图片库/相机权限或 Apple 登录 entitlement。读取 NSItemProvider 的 `UTType.url` / `UTType.plainText`，有输入数量上限。HTTPS 校验/32KiB payload 上限/SHA256 dedupe/7天过期清理均在共享模型。

数据流：第三方 Share Sheet → extension 读取 URL/text → `PendingRestaurantImportStore` 写 App Group JSON → completeRequest 返回第三方 App → 用户打开 Taste Map → 启动/scene active 读取待导入队列 → Restaurant acquisition preview/add flow。**扩展没有承诺自动唤起主 App，也没有使用不支持的 UIApplication 打开技巧**；当前文案明确“打开 App 后确认”。

App Group REQUIRED：两个 target 的 signed entitlement 均为 `group.com.lafayette.tastemap`。实际文件路径在 group container 的 `Library/Application Support/PendingRestaurantImports/v1`。`UserDefaults(suiteName:)` 在正式 target 中不是该共享机制；测试 fixtures/旧模板不构成共享权限需求。

主 App generated plist 本轮没有输出自定义 `TasteMapAppGroupIdentifier`；共享代码已有非 QA 的精确 fallback `group.com.lafayette.tastemap`，与扩展 plist 和双方签名一致，故不是缺 group/运行时错误。未无故新建容器或覆盖 plist。

Keychain Sharing NOT REQUIRED：无显式 keychain-access-groups，扩展不编译/调用认证存储。主 App auth、entitlement/deletion-resume storage 不因此需要跨 target Keychain。Share Extension 不直接访问主 App SwiftData 或相册/定位，也不直接网络上传分享 payload。

## 5. Location / Camera / Photos / Privacy

| 能力 | 实际调用 | Release permission key | 结果 |
|---|---|---|---|
| Location | CLLocationManager.requestWhenInUseAuthorization、前台 fix、accuracyAuthorization 分支 | NSLocationWhenInUseUsageDescription | PASS |
| Camera | Visit/Hybrid 用户主动 UIImagePickerController camera | NSCameraUsageDescription | PASS |
| Photos 输入 | PhotosPicker/PHPicker 用户所选图片 | 不申请整库读取 | PASS |
| Photos 保存 | AnalysisPosterPhotoLibrarySaver、PHPhotoLibrary .addOnly、创建保存资源 | NSPhotoLibraryAddUsageDescription | PASS |

PHOTOS：**PHOTOSPICKER INPUT + SAVE ONLY**，不是 FULL LIBRARY。UNUSED PERMISSION KEYS：NONE。没有 NSPhotoLibraryUsageDescription、Always location、background modes、麦克风/通讯录/跟踪等附加权限；没有为“保险”添加。

Apple 参考：[PhotosPicker 不需要整库授权](https://developer.apple.com/documentation/swiftui/view/photospicker(ispresented:selection:matching:preferreditemencoding:photolibrary:))、[Photos add-only purpose string](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSPhotoLibraryAddUsageDescription)。

主 App / extension 各自 PrivacyInfo.xcprivacy 与构建产物 byte parity PASS。主 App 申报 Name/Email/UserID/PurchaseHistory/PhotosorVideos/OtherUserContent/PreciseLocation/CoarseLocation/Contacts/ProductInteraction，全部不 tracking；与 `docs/TASTEMAP_DATA_COLLECTION_MAP.md` 中真实账号、到访地点、照片、应用内社交图谱一致。Contacts 指应用内社交图谱，不意味着读取手机通讯录。系统定位只是前台查询；存储的到访地点是 manifest location 声明的独立依据。

Required Reason API：主 App 自有文件时间 C617.1、app-local defaults CA92.1；extension 使用 JSON 队列、不读系统时间戳或共享 UserDefaults，空 RRA 数组符合当前调用。未新增共享 UserDefaults，不应添加对应 reason。

**线上 App Privacy 问卷本轮没有读取/截图证据**。没有发现本地代码↔manifest 的明确多报/漏报；不能由此推断 ASC 线上答案相同。三方 cross-check 仍 EVIDENCE INCOMPLETE，不重写 Privacy Policy。

## 6. 本轮验证与产物

审计专用输出目录：`/tmp/tastemap-release-capability-audit.RygTly`（mktemp 私有目录；系统可能清理，不是长期发布归档）。

```text
PROJECT: ios/TasteMap/TasteMap.xcodeproj
SCHEME: TasteMap
CONFIGURATION: Release
DESTINATION: generic/platform=iOS
BUILD: 1（沿用源码默认，仅审计，不安装、不提供为测试包）
VERSION: 1.0
APP: /tmp/tastemap-release-capability-audit.RygTly/DerivedData/Build/Products/Release-iphoneos/TasteMap.app
RENDERER POLICY: NATIVE_PRIMARY（本轮未运行，不宣称真机 renderer 确认）
IDENTITY FIELDS: unrecorded（没有冒充唯一测试 build identity）
SIGNER: Apple Development / 7G5J9MJX88
MAIN EXECUTABLE SHA256: 74e36b0aa86ad5f4ae879874bbce7e6eed7dc9dd6be2dc74d7d3d6c9e0e65e3f
EXTENSION EXECUTABLE SHA256: 4dc31e3de919254784e689b165f01298f34cb501eae78e817545faecdd949535
```

| 验证 | 结果 / 证据 |
|---|---|
| Xcode target enumeration | PASS，project-list.json |
| 主 App / extension resolved Release build settings | PASS，settings.json / extension-settings.json |
| 全新 DerivedData Release main + dependent Share Extension build | BUILD SUCCEEDED，build.log，22:55 CST |
| codesign --verify --deep --strict（主 App、每个 appex） | PASS |
| embedded identity/provisioning/certificate/entitlement compatibility | PASS，embedded-identity.json；未安装，因此未要求 device UDID gate |
| entitlement source↔signed diff、plist permission diff、configuration comparison | 44/44 PASS，capability-audit.json |
| Auth + release safety 本地 mock regression | 11/11 PASS，local-tests.log；无 Production D1 |
| 真机登录/分享/Universal Link | NOT RUN，按本轮范围 |
| Distribution export / Final Archive / App Store validation | NOT RUN，禁止提前生成 Final RC |

编译有既有 Swift concurrency/unused-variable 等 warning，以及无 AppIntents dependency 的 metadata warning；本轮无 build error，未扩展修改无关业务逻辑。运行前过早进行的一次 identity inspection 因 Info.plist 尚未生成失败；以 BUILD SUCCEEDED 后重跑的完整 PASS 为准，不把构建过程中的中间目录当签名产物。

复跑（在项目根目录）：

```sh
python3 scripts/audit-ios-release-capabilities.py /absolute/path/to/completed/TasteMap.app
python3 scripts/verify-ios-embedded-identity.py /absolute/path/to/completed/TasteMap.app --build ACTUAL_BUILD --bundle-id com.lafayette.tastemap
```

该检查不代替 distribution、线上 App Privacy 或 credential revocation 测试。不得用 `get-task-allow=true` 的本轮产物上传 TestFlight；未来经批准的 Final RC 必须独立重新构建并走 Distribution 签名/导出及完整验收。

## 7. 修改文件与后续一次性清单

本轮只新增：

1. `scripts/audit-ios-release-capabilities.py`：只读、无网络、无安装的可复跑配置/产物检查。
2. 本报告。

**没有修改**任何 entitlement、Info.plist、project/scheme、Apple capability、Bundle ID、Team、正式 staged Web assets、生产配置或认证协议。已有 dirty/concurrent changes 均保留。未发现处于本轮自动修复白名单内的明确配置错误，因此不为制造修改而加权限。

### USER ACTION REQUIRED（集中列出，不要求现在重复 StoreKit）

1. **Apple credential revocation 是代码待办，不是 Portal 勾选缺失**：需要另行批准补充 Apple user identifier 的安全存储/迁移、credential state + revocation lifecycle、账号 scope/Keychain 清理和回归；本轮没有请求用户撤销真实授权，也不能靠截图消除这个源码缺口。
2. **App Store Connect 隐私问卷核对**（本地审计无法替代）：位置 App Store Connect → My Apps → Taste Map → App Privacy（App 隐私）；打开现有数据类型/用途/关联/Tracking 详情。应看到与本报告第 5 节和数据映射一致的十类实际数据，全部不用于 tracking；App Functionality 与 Product Personalization 按数据映射逐类核对，不勾不存在的整库/通讯录/广告访问。先只查看；若不一致，提供页面截图/导出答案后集中确认修改，不盲目覆盖既有申报。证据须包含数据类型、用途、是否关联用户、是否用于 tracking。
3. **稍后批准的同一真机测试包，非本轮**：从其他 App 的 Share Sheet 分享支持的 HTTPS 餐厅链接 → Taste Map 扩展；应看到已接收提示，手动打开 Taste Map 后进入对应 preview/add flow。输入一个已知支持的公开餐厅链接，不填 code/token；提供带 build number、设备、时间的 cold/warm 录屏。
4. **稍后批准的 Universal Link 测试**：在 Notes/Messages 点击实际 `https://tastemap.cn/share/<有效公开分享ID>`（不是直接 Safari 地址栏自跳），分别 App 关闭/已启动；应进入匹配内容。Referral `/invite/*` 在当前 hold 下不得进入 attribution；不创建 B 账号、不消费 Sandbox code。提供 build number、设备、时间、链接类型及结果录屏；不包含私有分享内容/凭据。

无需用户新建 Identifier/App Group 或重加 Sign in with Apple；有效本地 provisioning 已证明现有权限可签。未来 Distribution export 属于独立 Final RC 步骤，不是本轮要求用户立即 Archive/上传的操作。
