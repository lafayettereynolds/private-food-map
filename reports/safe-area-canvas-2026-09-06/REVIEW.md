# 顶部安全区域与页面背景一致性

## 结果与原因

“我的”原先以白色绘制，而 Hybrid App Shell 的安全区域使用默认 `#F7F7F5`，因此状态栏下出现独立灰条。另有全局 `:root` 底色的优先级高于旧 `html` 样式，仅修改页面或内层容器不够。

现在由可见路由选择共用背景 token，HTML、body 和安全区域一起使用；保留原有安全区域高度，不增加遮盖条，不改变头像、统计、卡片、顶部按钮、底部导航或路由归属。保留在 DOM 中的隐藏 Profile/Discovery 不会影响当前页。

## 同类消费者清单

| 消费者 | 处理／边界 |
| --- | --- |
| Browser / Capacitor 的正式 Hybrid Profile | 根画布与 Profile 同用 `--color-surface`，解决白色页面上方灰条 |
| Hybrid Discovery / activity；Map / List chrome | 共用不透明 `--tm-browse-chrome-background`，浅色 `#F8FAFC`、深色 `#12191F`；移除两套局部半透明渐变背景，保留各自内容区与地图引擎 |
| Hybrid Add Restaurant；Browser acquisition | 把已有 acquisition 背景 token 提升为共享作用域，宿主与页面同色，浅深色不分叉 |
| Settings、Restaurant Detail、Lists、Roulette、Analytics、Premium | 保留已有页级画布；从 Profile 返回这些页面时默认 token 正确恢复，不把所有内容强制刷白 |
| 旧 Browser Profile / 公开 Profile、modal、普通网页宿主 | 无此 Hybrid 安全区域容器；不新增宿主样式覆盖；未改变照片、功能或可见性 |
| Native Profile / Settings / Discovery rollback | 使用既有 `TasteMapCoreTheme.page` 背景；Discovery 顶部和 `tasteMapCorePage()` 同色，不经过有缺陷的 CSS 壳层；未重绘或切换 renderer |
| Native acquisition、Share Extension、预览 | 既有 AcquisitionPalette 背景延伸安全区域／共用正式原生视图；无 Hybrid CSS 灰条根因，保持原有实现 |
| 辅助功能与系统状态栏 | 未改标签、焦点、最小点击区、系统状态栏样式或导航；仅背景颜色所有权修正 |

## 验证

- 99 项 Vitest 通过（全局产品、Map 产品和 Remaining UI 三组契约）。新增活动路由、共用 token、禁止隐藏页面决定画布及旧渐变覆盖的回归约束。
- `check-safe-area-canvas.mjs`：375 / 402 宽度 × 浅 / 深色 × 0 / 62px 顶部安全区域，共 8 组；每组 11 个路由及反复 Profile / Settings 返回，检查 HTML、body、shell、页面背景及安全区域高度。此为隔离 CSS probe，不是伪装成正式用户内容的测试数据。
- 固定 iPhone 17 Pro QA 模拟器 UI 测试 1 项通过，0 失败：我的 → 发现 → 地图 → 添加餐厅 → 返回 → 我的 → 设置 → 返回。保留真实运行截图，并停在“我的”供查看。
- 人工检查 Profile、Discovery、Add、Map 顶栏和 Settings 全屏截图。1206 × 2622 原始截图在 x=60、y=150/180/210（跨安全区域与内容）取样：Profile 首入和返回、Add 均为 `(255,255,255)`；Discovery/Map 为 `(248,250,252)`；Settings 为 `(247,247,245)`，每个页面内部三个样本完全一致。
- Map 截图在瓦片加载过程中，仅作为顶部 chrome 检查证据，不据此宣称地图手势、瓦片或真实定位验收通过。Add 的真实精确定位暂不可用状态被保留，没有以测试坐标伪造附近结果。

## 构建、运行身份与范围

- 分支 `feature/hybrid-final-integration`，基础提交 `58bd556b8382734aeae1f08937ba649563682140`；保留现有未提交用户改动，未 commit。
- `pnpm run hybrid:stage:formal` 通过：TypeScript、Worker typecheck、Vite build、17 个 dist/staged Web 文件逐字节一致。
- QA 构建 `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app` 的 17 个 Web 文件与 stage 一致。
- 固定模拟器 `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`，bundle `com.lafayette.tastemap.qa`，参数 `--tastemap-hybrid-development -AppleInterfaceStyle Light`，环境 `TASTEMAP_VISUAL_QA_MODE=rich`。React Hybrid 负责页面，地图仍为 Native MapKit；没有切换成 Native rollback 冒充新效果。
- 安装包：`/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/9E1BB79C-D7CD-4063-8E2D-86DEEFC7A7B7/TasteMap.app`。
- UI 证据 `/tmp/tastemap-safe-area-ui.xcresult`；Release `/tmp/tastemap-night-release/Build/Products/Release-iphoneos/TasteMap.app` 构建成功并通过纯净性扫描（39 App / 17 签名 Web 文件）。
- 没有修改业务算法、餐厅位置、用户记录、权限、付费逻辑、生产根路由或后端；未更新 iPhone 或发布。

## 截图

- [我的：首次进入](profile-initial.png)
- [我的：跨页面返回后](profile-returned.png)
- [发现](discovery.png)
- [添加餐厅](add.png)
- [地图顶栏](map.png)
- [设置](settings.png)

## Design System Compliance

- Core UI：PASS（本次范围）。由同一画布 token 贯穿安全区域，保留所有尺寸、字号、触控与层级。
- Food & Dining：未改照片、图标、头像或任何食物视觉。
- Canonical Page Templates：保持 Profile / Discovery / Acquisition / Settings 原有区块和顺序；本次只修正背景接缝。
- 重复实现：移除 Map / Discovery 深色顶栏局部渐变覆盖；无新增页面分支、遮盖条或重复组件。
- SwiftUI：无新增默认控件重绘，无 renderer / route ownership 变化。
- 剩余边界：深色检查证明同页背景一致，不代表整个 App 的深色视觉已经全面验收；真实 iPhone、地图瓦片／手势、实际定位不属于本次验收。最终视觉仍接受 Lafayette 查看反馈。

长期规则已写入 `TASTEMAP_PRODUCT_DESIGN_RULES.md` 的 Theme Boundaries。
