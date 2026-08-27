# Taste Map iOS / Mac 发布前检查清单

更新时间：2026-08-26

本文件只记录 Windows 无法完成的 Xcode、签名和真机验证工作。`ios/` 中的 Share Extension、App Group 待处理导入、主 App 确认页和 API 协议源码已经就绪，但不代表已经生成可安装的 iOS App。

## 1. Xcode 工程与 Target

- [ ] 在 Mac 上创建或打开 Taste Map iOS 主 App Target。
- [ ] 创建 Share Extension Target，并将 `ios/ShareExtension/` 加入该 Target。
- [ ] 将 `ios/Shared/` 同时加入主 App 与 Share Extension Target。
- [ ] 将 `ios/TasteMapApp/` 加入主 App Target。
- [ ] 确认最低 iOS 版本、Swift 版本和 Bundle Identifier 与正式账号配置一致。

## 2. App Group 与深链

- [ ] 在 Apple Developer 与两个 Target 中创建同一个 App Group，例如 `group.com.yourcompany.tastemap`。
- [ ] 将示例 entitlements 中的 App Group 替换为正式值，确保主 App 与扩展完全一致。
- [ ] 配置 Taste Map URL Scheme 或 Universal Link。
- [ ] 主 App 通过 `onOpenURL` / Scene 生命周期接收 `importId`，不得把原始 URL 或分享文本放进深链。
- [ ] 验证待处理记录只能由创建它的当前账号读取，过期和重复记录会被清理。

## 3. 登录与网络

- [ ] 为 `ExternalImportCoordinator` 注入主 App 的真实登录授权；Share Extension 不保存访问令牌。
- [ ] 确认调用的是当前环境的 `/api/external-place/resolve`，测试和正式环境不可串用。
- [ ] 离线、登录过期、请求超时和解析失败都能保留待处理记录并允许重试。

## 4. Share Extension 激活规则

- [ ] Safari、Apple Maps、高德或其他 App 分享 URL 时显示 Taste Map。
- [ ] 只分享普通文本时也显示 Taste Map，并可提取其中的 URL 或餐厅线索。
- [ ] 不支持的附件类型不激活扩展，避免错误接收图片、视频或大文件。
- [ ] 扩展轻量完成保存后立即打开主 App，不在扩展中执行完整抓取或 POI 搜索。

## 5. 必测场景

- [ ] Apple Maps 单一明确门店。
- [ ] Apple Maps 多个同名门店，必须选择。
- [ ] 高德地图门店链接。
- [ ] 普通餐厅官网或结构化网页。
- [ ] 仅包含餐厅名称/地址的分享文本。
- [ ] 短链接与 3–5 次以内的安全重定向。
- [ ] 同名或模糊候选，不得静默选第一家。
- [ ] 地址不完整，进入现有搜索确认。
- [ ] 跨城市餐厅，保留链接证据中的城市与坐标。
- [ ] 已存在餐厅，复用现有身份而不重复创建。
- [ ] 未知或不支持的 URL，明确失败且可手动搜索。
- [ ] 待处理导入过期。
- [ ] 离线保存后恢复网络重试。
- [ ] 同一内容重复分享，避免重复待处理任务。
- [ ] 切换账号后拒绝读取其他账号的待处理导入。
- [ ] localhost、私网 IP、云元数据地址及跳转到这些地址的链接均被拒绝。

## 6. 签名、隐私与发布

- [ ] 主 App 与 Share Extension 使用正确 Team、证书和 Provisioning Profile。
- [ ] Release 构建确认 App Group、Associated Domains/URL Scheme 和网络权限没有丢失。
- [ ] 隐私说明明确外部链接只用于识别餐厅；不导入第三方评分、评论或照片。
- [ ] 真机验证扩展启动时长、内存、系统分享取消、后台恢复和冷启动。
- [ ] Archive 前跑完主 App 与扩展测试，并在 TestFlight 再验证一次完整分享链路。

## Windows 已验证

- [x] Web 粘贴链接入口与候选确认流程。
- [x] Worker 解析 API、身份保护和 URL 安全限制。
- [x] 高德链接生成候选但不自动保存。
- [x] 不安全链接结束加载并显示错误。
- [x] 390px 手机视口没有横向溢出。
- [x] TypeScript、自动测试和正式 Web 构建通过。
