# Taste Map Hybrid Migration Phase 1 Foundation

日期：2026-09-02
分支：`feature/hybrid-foundation-app-shell`
独立 Worktree：`/Users/lafayette/Projects/private-food-map-hybrid-foundation`
基础 commit：`7bd7cddabe8296b6c9ffb9d7a56965fc3dd6c42c`
正式产品基线：`3beab169782bef76210b61042d45720e829f1aa6`

## 结论

1. **Phase 1：PASS**
2. **Capacitor Foundation 是否正式化：是**
3. **App Shell 是否成立：是**
4. **Bridge v1 是否成立：是**
5. **Platform Adapter 是否成立：是**
6. **Profile：`HYBRID_READY`**
7. **Restaurant Detail：`HYBRID_READY`**
8. **Browser 是否未受损：是**
9. **Offline 是否可启动：是**。Hybrid UI、字体与资源全部来自签名 App 内的本地 bundle；Debug fixture 可在没有远端 UI 服务时完成启动和本地数据渲染。真实 iPhone 飞行模式 smoke 留到正式集成阶段，不以本报告冒充已执行。
10. **Release purity：CLEAN**
11. **Current SwiftUI 是否完整保留：是**
12. **是否修改正式 Release 默认入口：NO**
13. **下一阶段建议：先做正式 App Shell / Navigation 集成，再迁 My Map / My List；本轮未开始 Phase 2。**

`HYBRID_READY` 只表示页面、数据合同、Browser/Native adapter、路由与回退边界已经具备正式迁移基础；不等于 `HYBRID_PRIMARY`，也没有切换正式 Release 入口。

## 1. Git 与隔离边界

- 当前正式工作目录 `/Users/lafayette/Projects/private-food-map-product-ux` 保持原分支和原有未提交用户内容，未被修改、清理、stash 或覆盖。
- 本轮只在独立 worktree 与专用分支中实现。
- Phase 1 从已通过的 Capacitor POC commit 开始，但已移除正式代码中的 `POC` 命名、临时 route、单用途 fixture injection 和重复配置。
- 历史 POC 报告、截图和 Git 历史均保留，未删除证据。
- 未 merge `main`，未改正式 Release 默认入口，未访问 Production。

## 2. 正式目标架构

```text
One React UI
├── Browser → TasteMapBrowserAdapter → IndexedDB / Browser services
└── Capacitor iOS → TasteMapNativeAdapter → TasteMapNative.v1
                                         → existing Native services / SwiftData

SwiftUI current app → production owner and rollback path during migration
```

React UI 不直接读取 SwiftData、Keychain、文件路径或原生 service。页面只依赖 `TasteMapPlatform`。Browser 与 Native 的差异全部收口在 adapter/bridge 层。

详细 ADR：[TASTEMAP_HYBRID_ARCHITECTURE.md](../../docs/TASTEMAP_HYBRID_ARCHITECTURE.md)
迁移矩阵：[TASTEMAP_HYBRID_MIGRATION_STATUS.md](../../docs/TASTEMAP_HYBRID_MIGRATION_STATUS.md)

## 3. Capacitor Foundation

- 正式目录统一为 `hybrid/`；活跃实现不再使用 `hybrid-poc` 命名。
- Capacitor app 使用独立 internal Bundle ID：`com.lafayette.tastemap.hybrid.internal`。
- `webDir` 指向本地打包产物；配置中没有 production `server.url`。
- iOS 壳通过本地 Swift Package 引入 `TasteMapHybridBridge`，没有复制另一套 Native 数据实现。
- 构建脚本覆盖：Hybrid Web、Capacitor sync、固定 Simulator Debug、Release Simulator、Generic Device Release、Release binary purity scan。
- Release 日志关闭，Debug fixture 只在 `#if DEBUG` 中编译。

## 4. App Shell 与 Navigation Ownership

App Shell 负责：

- runtime/capability handshake；
- auth session shape；
- Profile 启动数据；
- Hybrid route 注册；
- Restaurant Detail 内部导航与 back contract；
- Native-primary handoff；
- loading/auth-required/fatal/offline 状态；
- safe-area；
- Debug-only diagnostics。

当前 route registry：

| Surface | Status | Phase 1 行为 |
| --- | --- | --- |
| Profile | `HYBRID_READY` | React UI + Browser/Native adapter |
| Restaurant Detail | `HYBRID_READY` | React UI + Browser/Native adapter |
| Map / Discovery / Add Restaurant | `NATIVE_PRIMARY` | 仍由原生正式路径承载 |
| Visit / Lists / Roulette / Analytics | `NATIVE_PRIMARY` | 未迁移 |
| Premium / Settings | `NATIVE_PRIMARY` | 未迁移 |

Deep link contract 仅解析 allowlist 中的 Restaurant/Profile/List/Activity；解析本身不执行跳转，也不信任任意 URL。

## 5. `TasteMapNative.v1` Bridge

Bridge 使用单一 versioned invoke envelope：

- `version`
- `requestID`
- `method`
- typed payload
- typed success/error response

Phase 1 方法包括：

- `runtime.info`
- `auth.sessionStatus`
- `profile.current`
- `restaurant.detail`
- `navigation.openNative`
- `haptics.selection`

Capability registry 显式声明可用能力；UI 不能根据平台名称猜测能力。结构化错误覆盖版本不匹配、非法请求、未登录、未找到、能力不可用和内部失败。

## 6. 数据、安全与 Ownership

- Bridge 不返回 access token、refresh token、Apple subject、Keychain 内容或 Authorization header。
- 不向 Web UI 暴露绝对本地路径、SwiftData object、文件 URL 或数据库实现细节。
- Profile 与 Restaurant DTO 查询均通过 current-user ownership predicate。
- Browser projection 保留真实 Profile 用户 ID，同时将 React 旧组件中的“当前查看者”语义映射到稳定 viewer sentinel，避免把 owner-scoped record 误判为其他用户记录。
- Restaurant image descriptor 遵守当前 `RestaurantImagePriorityPolicy`；Bridge 只输出可呈现 descriptor，不泄露内部存储路径。
- Debug fixture 使用独立 in-memory SwiftData container 和 isolated session，不触碰真实 Keychain/账号/Production。
- Native data/security full regression 全部通过，包括多账号隔离、Sync、Backup/Import 与 F1-C4 exact duplicate Visit 回归。

## 7. Browser 与 Native Adapter

`TasteMapPlatform` 是 UI 唯一平台边界。

- `TasteMapBrowserAdapter` 继续使用 Browser data source / IndexedDB。
- `TasteMapNativeAdapter` 只调用 `TasteMapNative.v1`，并验证 bridge version、request ID、payload 和结构化错误。
- 两个 adapter 输出相同 UI view model。
- Browser build 使用原正常入口；Hybrid build 使用 App Shell 入口。Browser 产品页面未被替换或降级。

## 8. 视觉与真实 Simulator 证据

固定设备：iPhone 17 Pro，iOS 26.5，UDID `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`。未 clone、未 erase、未更换设备。

- [Hybrid Foundation Profile](./phase-1/screenshots/hybrid-foundation-profile.png)
- [Hybrid Foundation Restaurant Detail](./phase-1/screenshots/hybrid-foundation-restaurant-detail.png)
- [Profile：Browser vs Phase 1](./phase-1/screenshots/profile-browser-vs-phase-1.png)
- [Restaurant Detail：Browser vs Phase 1](./phase-1/screenshots/restaurant-browser-vs-phase-1.png)
- [Profile cold-start 1.0s checkpoint](./phase-1/screenshots/profile-cold-1.0s.png)

检查结果：

- Profile 和 Restaurant Detail 使用同一 React 产品 UI；
- POC 的字体、spacing、图片、safe-area 和页面构图未退化；
- Restaurant Detail Native DTO 显示真实评分 `9.0`，不存在 viewer identity 投影导致的 `NaN`；
- Debug app 最终停留在 Profile，供 Lafayette 继续检查；
- macOS Accessibility 无法读取 WKWebView 内部 DOM，实际页面点击不作为伪造的自动化通过证据；navigation/back 由 route registry 测试、App Shell contract 与两页真实 Simulator render 共同覆盖。

## 9. 测试与 Build

| 验证 | 结果 | 证据摘要 |
| --- | --- | --- |
| TypeScript Hybrid tests | PASS | 2 files / 7 tests |
| Swift Bridge tests | PASS | 4 tests |
| Browser production build | PASS | 正常 Browser 入口未受损 |
| Hybrid local bundle verification | PASS | 本地资源、无 `server.url` |
| Fixed Simulator Debug build/install/launch | PASS | iPhone 17 Pro / iOS 26.5 |
| Hybrid Release Simulator build | PASS | Capacitor Release shell |
| Hybrid Generic Device Release build | PASS | `CODE_SIGNING_ALLOWED=NO`；未改变 Team/Signing |
| Formal SwiftUI full unit/integration | PASS | 631 tests / 64 suites，58.764s |
| Formal SwiftUI Release Simulator | PASS | Main App + Share Extension |
| Native multi-account isolation | PASS | current-user ownership regressions retained |
| F1-C4 duplicate Visit exact regression | PASS | second identical import → exactDuplicate → no second Visit/no extra mutation |
| Release binary purity scan | CLEAN | 实际 `.app` 37 files recursively scanned |

本轮按任务边界没有运行与本次改动无关的旧全量 screenshot UI suite；Hybrid 视觉使用固定 Simulator 的真实构建截图验收。

## 10. Release Purity

实际 Release `.app` 主体和资源递归扫描确认未包含：

- Debug fixture data / Rich Demo user；
- Visual QA runtime；
- fake Premium entitlement；
- test auth/header/credential implementation；
- Development API URL；
- remote Capacitor `server.url`；
- token、secret、private-key marker；
- 本机绝对工作目录；
- Debug-only route/diagnostic activation。

`VITE_HYBRID_DEBUG_ROUTE` 只存在于 internal Debug build；Release 分支编译时不生成对应逻辑或字符串。正式 Taste Map Release 默认仍是现有 SwiftUI app。

## 11. 性能基线

| 指标 | Phase 1 |
| --- | ---: |
| `simctl launch` command dispatch | 0.26s / 0.16s / 0.17s；median 0.17s |
| Bridge runtime init | 59.35 ms |
| Auth session status | 0.96 ms |
| Profile DTO load | 12.00 ms |
| Restaurant Detail DTO load | 12.84 ms |
| Profile full render checkpoint | cold launch 后 1.221s 内完整可见 |
| Debug App process RSS | 246,928 KB（约 241 MiB） |
| Debug Simulator `.app` | 9.6 MB |
| Release Simulator `.app` | 8.3 MB |
| Release Device `.app` | 5.0 MB |

注意：当前 RSS 是 App 进程，不含可能独立运行的 WebContent 总和。Phase 2 应增加可重复的全进程内存/交互首帧 signpost，而不是用不完整指标伪报优化完成。Browser 主入口仍有既有约 745 KB Vite chunk warning，未因本轮架构改动扩大为 Release blocker，但应在后续 page-level code splitting 中处理。

## 12. 当前未迁移与后续 Gate

以下不是 Phase 1 失败，而是刻意留给后续阶段：

- 正式 Taste Map target 内的 Hybrid Shell ownership/integration；
- real Auth lifecycle、真正 current-user Bridge session 与原生导航 handoff；
- Visit/write/mutation、Sync capability 的正式 bridge implementation；
- My Map、Discovery、Add Restaurant、Visit、Lists、Roulette、Analytics、Premium、Settings 页面迁移；
- Universal Link / Share Extension 到 Hybrid route 的正式接入；
- 真实 iPhone offline、background/foreground、memory pressure、deep-link smoke；
- Aggregate App + WebContent memory instrumentation；
- Browser/Hybrid route-level code splitting。

## 13. Phase 2 建议（未执行）

建议下一阶段顺序：

1. 将 App Shell / navigation ownership 安全接入正式 target，但保留 SwiftUI rollback；
2. 完成 real Auth/session、deep-link 和 Native-primary handoff；
3. 迁移 My Map / My List，优先验证 Map 原生能力与 React UI 的边界；
4. 然后依次评估 Discovery、Add Restaurant/Nearby、Visit、Lists、Roulette、Analytics、Premium/Settings。

本报告生成后 Phase 1 停止，不自动执行 Phase 2。
