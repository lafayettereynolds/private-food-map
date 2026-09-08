# 设置：会员权益前置

会员权益现在独立成组，紧接账户与安全，排在数据与备份、同步、隐私／权限和存储前面。原有“存储与 Premium”拆开，存储仍是后面的工具类设置。没有新增营销大卡片，没有改变会员能力、价格、付费状态或订阅操作。

## 变更与同类入口

| 入口 | 本次处理 |
| --- | --- |
| TasteMapSettingsPage，正式 React Browser / Capacitor 共用设置 | 将唯一 Premium 行移动到“账户”之后的“会员权益”分组；保留原始 onOpenPremium / typed navigation 回调、busy 防重入和会员／免费用户文案 |
| TasteMapSettingsView，Native 设置及 rollback | 将同一 PremiumSettingsView NavigationLink 移到第二组“会员权益”，保持 settings-premium-entry 标识和会员状态来源 |
| SettingsModal，旧 Browser 数据与设置总览 | 原本已将会员与订阅放在数据之前，保留；仅存储／导出／导入详情不新增不相关会员入口 |
| SettingsPreviews / Native handoff | 引用正式 Settings View，自动继承顺序；账户／权限等具体详情仍进入对应页面，不重新展开设置总目录 |
| Profile Premium badge / paywall / 分享扩展 | 不是设置索引排序，未改动；扩展无此设置目录 |

## 验证与边界

- 83 项 Vitest 通过，包含 paid/free Settings 精确分组顺序、单一 Premium 行、Native 相同优先级、原有账户与权限交互契约。
- `check-settings-membership-priority.mjs` 在隔离浏览器验证会员／免费用户、375／402px、浅色／深色：会员行在账户后、备份前，首屏可见且点击触发既有回调。浏览器实测会员行 y=259.17px、高 67px；不是把入口移到不可见位置后仅检查源码。
- 固定 QA 模拟器 2 项 UI 测试通过：会员首屏位置、实际打开会员权益、返回仍在设置，以及相邻账户入口回归（0 失败）。
- 独立 Native regression 模拟器 1 项 UI 测试通过：相同优先级和真实 PremiumSettingsView 跳转（0 失败）。使用显式离线测试账号，不触及真实账户或 iPhone。
- 没有执行购买、恢复购买、订阅变更、导出／导入、清理数据或账户操作。测试会员状态仅为 QA 布局证据，不代表真实订阅验证。

## 运行身份

- 分支 `feature/hybrid-final-integration`，基础提交 `58bd556b8382734aeae1f08937ba649563682140`；保留用户已有未提交改动，未提交代码。
- React Hybrid QA：`/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`，bundle `com.lafayette.tastemap.qa`，固定模拟器 `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`；参数 `--tastemap-hybrid-development -AppleInterfaceStyle Light`，`TASTEMAP_VISUAL_QA_MODE=rich`；路径 我的 → 设置 → Premium → 返回。
- Native rollback：`/tmp/tastemap-map-anchor-tests/Build/Products/Debug-iphonesimulator/TasteMap.app`，bundle `com.lafayette.tastemap`，专用模拟器 `5C24CBC2-5E24-4D82-B7DD-FB815DD7A60A`；显式 P1D / P3A / F1B3 离线测试模式；路径 我的 → 设置 → Premium。
- UI 结果：`/tmp/tastemap-premium-order-hybrid.xcresult`、`/tmp/tastemap-premium-order-native.xcresult`。正式 stage 的 TypeScript 检查、build 和 dist/staged 相等校验均通过；QA built 与 installed 的 17 个 Web 文件均逐字节匹配。
- 已安装 QA App：`/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/473CE699-CAB8-49AF-A49D-E4A173F9CC8F/TasteMap.app`。
- Release 构建成功；`/tmp/tastemap-night-release/Build/Products/Release-iphoneos/TasteMap.app` 纯净性扫描通过（39 个 App 文件、17 个签名 Web 文件）。没有 Debug 开关、fixture、Development URL、本地路径或 secret 混入正式资源。
- 未更换生产根路由，未更新真实 iPhone，未发布后端或 App。

## 实际画面

- [Hybrid 设置首屏](hybrid-settings.png)：账户之后独立显示会员权益；测试结束停留在此页供查看。
- [Hybrid 会员权益目标页](hybrid-benefits.png)：点击原始入口到达会员权益与管理页面。
- [Native 设置首屏](native-settings.png)：原生回退入口遵循相同顺序。
- [浏览器会员状态](browser-member.png)、[浏览器免费状态](browser-free.png)：两类状态都保持第一屏入口。

以上截图均来自运行中的页面，不是设计稿。已人工查看 Hybrid 与 Native 首屏，会员权益位置符合本次要求。

## Design System Compliance

- Core UI：复用 SettingsSection / HybridEntryRow 与原生 SettingsDestinationLabel，只调整分组和顺序，维持字号、图标、间距和点击区域。
- Food & Dining：未改会员汉堡标识、paywall hero 或任何餐厅视觉。
- Canonical Page Templates：最新用户要求仅覆盖会员入口优先级；其余设置分组顺序、唯一账户详情、明确返回路径和高风险操作边界保留。
- 重复组件：两个正式渲染入口都按相同规则调整；旧 Browser 总览原已靠前，不再添加第二个入口。未新增控件或页面分支。
- SwiftUI：复用现有 approved native-density 设置样式，没有以默认新页面重绘；原生独立截图和 Hybrid 截图区分保存。
- 剩余范围：本次不验证实际付费/续费交易或其他页面布局；用户仍可对实际首屏效果提出调整。

长期规则已同步到 `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` 的 Settings membership priority。
