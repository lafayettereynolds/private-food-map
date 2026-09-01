# Taste Map — Dynamic Type P1 Closure

## Closure status

**CLOSED**

在固定的 iPhone 17 Pro / iOS 26.5 Simulator（UDID `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`）上，已用真实系统字号分别验证 Default、Accessibility Large、Accessibility Extra Extra Large。确认本专项涉及的 Profile、Discovery、Roulette、Bottom Add Restaurant CTA、主 Tab / Navigation 在 Accessibility Extra Extra Large 下关键内容完整、可读、可操作；页面可以滚动，CTA 不再与 Tab 重叠，标准字号没有明显视觉回归。

本次只修改 SwiftUI 布局和专项 UI 验收测试，没有修改业务逻辑、数据模型、SwiftData schema、API、Worker、D1/R2、Auth、Sync、Import/Backup、StoreKit、Production、Signing/Capabilities、主题颜色或品牌视觉。

## Audit environment

| 项目 | 值 |
| --- | --- |
| Branch | `fix/product-ux-correction-8-tasks` |
| 开始时 HEAD | `8851f63f59a602591665d375bf6c7cf773b3107a` |
| 开始时 origin branch | `8851f63f59a602591665d375bf6c7cf773b3107a` |
| Device | iPhone 17 Pro |
| OS | iOS 26.5 |
| UDID | `E4F3EED9-89D8-405C-B4CB-7CA816CE3405` |
| Appearance | Light |
| 验证字号 | Default / Accessibility Large / Accessibility Extra Extra Large |
| UI 数据 | 既有 DEBUG-only、内存隔离的 rich fixture；未修改现有测试用户状态 |

没有创建、Clone 或 erase Simulator。系统字号在验证期间按任务要求切换，最终恢复为 Default（`large`）。BEFORE 与 AFTER 均通过实际运行 App 取得，不是根据旧报告推测。

## Executive findings

这 5 类回归有一个共同成因：标准字号成立的横向密度和固定高度，被无条件沿用到 Accessibility 字号。修复策略不是缩小字体或截断信息，而是在 `dynamicTypeSize.isAccessibilitySize` 时切换容器拓扑，让文字获得纵向空间；非 Accessibility 分支继续使用原布局。

| 页面 / 区域 | 原始问题 | Root Cause | 修复后的 layout assumption | 为什么不破坏 Default |
| --- | --- | --- | --- | --- |
| Profile | 身份、社交指标、基础统计和 dashboard tile 在 XX Large 下截断、拥挤；部分文本近似竖排 | 多个 `HStack`、2/3 列固定网格、单行数值和缩放假设同时争夺横向空间 | Accessibility 下身份块、社交指标、统计改为纵向；dashboard 改为单列；重要文本允许纵向增长 | Default 仍走原横排、2/3 列和既有尺寸分支，字体、间距、卡片视觉未改 |
| Discovery | 副标题、餐厅名/地址、来源/评分、quick actions 在 XX Large 下截断或失衡 | `lineLimit(2)` 与高密度横排 / 两列 action grid 限制内容高度和宽度 | 重要标题完整 wrap；Accessibility 下来源/评分纵排，actions 单列 | Default 保留原 HStack、两列 fallback、来源左/评分右与两行卡片密度 |
| Roulette | 候选标题/计数/清空、条件 chips、摘要/管理按钮、结果 actions 和转盘中心文案裁切 | 候选区和按钮区假设可在一行容纳；34pt 控件与 30% 固定中心圆无法容纳大字号 | Accessibility 下 header/summary/results 纵排，条件横向滚动；管理和筛选控件至少 44pt；中心圆扩大并使用一个自适应主动作标签 | Default 保留原横排、34pt filter、30% 中心圆和两行中心文案；转盘逻辑、候选池和结果逻辑未改 |
| Bottom Add Restaurant CTA | CTA 与 Tab 被塞进固定 88pt ZStack，XX Large 下相互重叠并挤压 | 38pt 浮动 CTA + 58pt Tab + 30pt overlay offset 只在标准字号成立 | Accessibility 下 CTA 与 Tab 成为有 intrinsic height 的纵向区域；CTA 至少 44pt，Tab item 保持纵排语义 | Default 完整保留原 88pt ZStack、38pt Capsule、阴影和位置 |
| Navigation / Tab Bar | XX Large 下底栏视觉上像横向拥挤/滚动，CTA 覆盖 Tab，命中区不可可靠区分 | 自定义底栏固定高度不足，而不是系统 TabView 的合理原生滚动行为 | 保留三项 Tab 的固定产品信息架构，用等宽三列、可增高文字和独立 CTA 行消除重叠 | Default 的 Tab 图标、标题、选择态、位置与间距保持原样；没有禁用 Dynamic Type |

## Page-level closure

### Profile

- 身份卡在 Accessibility 字号下由横排切到纵排；头像、姓名、bio、metadata、编辑和社交入口不再争夺同一行。
- 关注/粉丝和去过/想去/总消费统计在 Accessibility 字号下纵向 reflow，数值不再使用 `minimumScaleFactor` 掩盖空间不足。
- “今天吃什么”、口味档案、回味、食单、分析等 dashboard 模块在 Accessibility 字号下使用单列，保持原 section 顺序和导航语义。
- tile / compact row 的关键标题与说明使用垂直 intrinsic size，不再用两行截断重要内容。
- 实际滑动进入 Roulette 的 UI test 证明长页面仍可滚动，且入口可点击。

修改文件：

- `ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift`

### Discovery

- Discovery 顶部说明移除两行上限，允许完整纵向增长。
- 餐厅名和地址在 Accessibility 字号下不设两行上限。
- 来源用户与活动评分在 Accessibility 字号下改为纵排，避免互相挤压。
- 餐厅 quick actions 在 Accessibility 字号下改为单列；Default 继续使用原横排 / 两列 fallback。
- 五个 Discovery 主 Tab、城市菜单、筛选、filter chip strip 的信息架构和顺序不变。

修改文件：

- `ios/TasteMap/TasteMap/App/RootTabView.swift`
- `ios/TasteMap/TasteMap/Features/Discovery/DiscoveryView.swift`

### Roulette

- 候选池标题、计数、清空按钮在 Accessibility 字号下纵排。
- 条件 chips 在 Accessibility 字号下使用横向 ScrollView；信息不截断，也不改变筛选含义。
- 候选摘要和管理按钮纵排，管理按钮至少 44pt。
- 结果 actions 在 Accessibility 字号下纵排。
- 转盘中心圆仅在 Accessibility 字号下由直径 30% 增至 50%，中心动作保留一个完整主标签（开始 / 再抽 / 抽取中），其 VoiceOver label/hint 继续表达完整动作；Default 的双行中心文案和原尺寸不变。
- 候选数量、最多 10 个轮盘 segment 与完整候选池随机逻辑未修改。

修改文件：

- `ios/TasteMap/TasteMap/Features/Roulette/RestaurantRouletteView.swift`

### Bottom Add Restaurant CTA and Navigation

- Accessibility 字号下使用 CTA 在上、Tab 在下的 intrinsic-height `VStack`，不再把两层内容叠进固定 88pt。
- CTA 的 Accessibility 命中高度至少 44pt；Tab item 原有最小高度 50pt，并增加 Accessibility 垂直 padding。
- 三个 Tab 保持等宽、非滚动、图标在上文字在下；选择态 trait 和 accessibility label 保留。
- 推入 Roulette 后底部 CTA 正确消失，NavigationStack 返回语义不受影响。

修改文件：

- `ios/TasteMap/TasteMap/Components/TasteMapBottomNavigation.swift`

## Screenshot evidence

所有截图均为固定 Simulator 上的 1206 × 2622 原始屏幕截图。

### BEFORE — Accessibility Extra Extra Large

| 范围 | 证据 |
| --- | --- |
| Profile（rich） | [profile-rich-accessibility-extra-extra-large.png](before/profile-rich-accessibility-extra-extra-large.png) |
| Profile（signed out） | [profile-signed-out-accessibility-extra-extra-large.png](before/profile-signed-out-accessibility-extra-extra-large.png) |
| Discovery | [discovery-rich-accessibility-extra-extra-large.png](before/discovery-rich-accessibility-extra-extra-large.png) |
| Roulette | [roulette-rich-accessibility-extra-extra-large.png](before/roulette-rich-accessibility-extra-extra-large.png) |
| My Map / Add CTA / Navigation | [map-add-cta-navigation-accessibility-extra-extra-large.png](before/map-add-cta-navigation-accessibility-extra-extra-large.png) |

### AFTER — Default

| 范围 | 证据 |
| --- | --- |
| My Map / Add CTA / Navigation | [map.png](after/default/map.png) |
| Discovery | [discover.png](after/default/discover.png) |
| Profile | [profile.png](after/default/profile.png) |
| Roulette | [roulette.png](after/default/roulette.png) |

### AFTER — Accessibility Large

| 范围 | 证据 |
| --- | --- |
| My Map / Add CTA / Navigation | [map.png](after/accessibility-large/map.png) |
| Discovery | [discover.png](after/accessibility-large/discover.png) |
| Discovery UI-test state | [discovery-ui-test.png](after/accessibility-large/discovery-ui-test.png) |
| Profile | [profile.png](after/accessibility-large/profile.png) |
| Profile scrolled | [profile-scrolled.png](after/accessibility-large/profile-scrolled.png) |
| Roulette scrolled | [roulette.png](after/accessibility-large/roulette.png) |

### AFTER — Accessibility Extra Extra Large

| 范围 | 证据 |
| --- | --- |
| My Map / Add CTA / Navigation | [map-add-cta-navigation.png](after/accessibility-extra-extra-large/map-add-cta-navigation.png) |
| Discovery | [discovery-rich.png](after/accessibility-extra-extra-large/discovery-rich.png) |
| Discovery UI-test state | [discovery-rich-ui-test.png](after/accessibility-extra-extra-large/discovery-rich-ui-test.png) |
| Profile | [profile-rich.png](after/accessibility-extra-extra-large/profile-rich.png) |
| Profile scrolled | [profile-rich-scrolled.png](after/accessibility-extra-extra-large/profile-rich-scrolled.png) |
| Roulette scrolled | [roulette-rich.png](after/accessibility-extra-extra-large/roulette-rich.png) |

## Three-size acceptance matrix

| 检查项 | Default | Accessibility Large | Accessibility Extra Extra Large |
| --- | --- | --- | --- |
| 关键文字 / 数值完整 | PASS | PASS | PASS |
| 按钮文字完整 | PASS | PASS | PASS |
| CTA 与 Tab 不重叠 | PASS | PASS | PASS |
| Tab 互不重叠、均可点击 | PASS | PASS | PASS |
| Profile 可滚动并进入 Roulette | PASS | PASS | PASS |
| Discovery 五 Tab / 城市 / 筛选可用 | PASS | PASS | PASS |
| Roulette 候选与管理按钮可用 | PASS | PASS | PASS |
| 44pt Accessibility 点击目标 | N/A（保持既有视觉） | PASS | PASS |
| 页面结构符合当前产品模板 | PASS | PASS | PASS |
| 明显视觉回归 | 无 | 无 | 无；允许 Accessibility reflow |

Default 视觉核对结论：spacing、字体层级、卡片尺寸、原横排信息、页面留白和品牌视觉均无明显变化。Accessibility 下发生的纵向重排是为了可读性和操作性，未反向影响标准字号分支。

## Accessibility semantics and interaction

- Bottom CTA 继续暴露“添加餐厅”；三个主 Tab 继续暴露各自 label 和 selected trait。
- Profile 编辑、关注/粉丝、找人、dashboard navigation 的既有 identifiers / labels 没有因容器重排丢失。
- Discovery 五 Tab、城市、筛选、餐厅 action 和来源用户仍通过 Accessibility tree 可查询和点击。
- Roulette 的筛选按钮仍为“调整候选条件”；spin button 保留完整 accessibility label/hint；结果 card 的组合 label 保留。
- XCUITest 在真实 Accessibility Large 与 Extra Extra Large 下验证 CTA、三个 Tab、Profile Roulette 入口、Discovery controls、Roulette 管理按钮均 `isHittable`。
- CTA 最小高度 44pt；Tab item 最小高度 50pt；Accessibility 下 Roulette filter 与管理候选按钮至少 44pt。
- Profile 的真实 swipe/scroll 路径在 UI test 中成功执行，说明大字号长内容可以到达而不是被固定容器截断。

## Automated test results

| 验证 | 结果 | 产物 |
| --- | --- | --- |
| Debug Simulator build（修复后） | PASS | `/tmp/TasteMapDynamicTypeP1DerivedData` |
| 新增 Dynamic Type P1 UI contract — Accessibility Large | 1 test, 0 failures | `/tmp/DynamicTypeP1AccessibilityLarge.xcresult` |
| 新增 Dynamic Type P1 UI contract — Accessibility Extra Extra Large | 1 test, 0 failures | `/tmp/DynamicTypeP1XXLarge.xcresult` |
| Default 核心页面 + Roulette focused UI regression | 2 tests, 0 failures | `/tmp/DynamicTypeP1DefaultParity.xcresult` |
| 完整 `TasteMapTests` unit/integration suite | 64 suites, 629 tests, 0 failures | `/tmp/DynamicTypeP1UnitSuite.xcresult` |
| `git diff --check` | PASS | 无 whitespace error |

新增的 `testDynamicTypeP1AccessibilityExtraExtraLargeClosure` 验证：

- Bottom CTA 和三个 Tab 可点击。
- CTA 的 `maxY <= Tab.minY`。
- 三个 Tab frame 两两不相交。
- Profile 可以滚动到 Roulette 入口并完成导航。
- push 到 Roulette 后底部 CTA 不存在。
- Roulette 候选数存在，管理按钮可点击且高度至少 44pt。
- Discovery header、主 Tab、城市、筛选、Add CTA 可点击，CTA 与 Tab 不相交。

完整 UI atlas 含大量跨业务和远端状态用例，不属于本次布局专项的合理全量执行范围；本次执行了完整 629 项 unit/integration suite，并在三档真实系统字号执行直接覆盖修改页面的 focused UI contracts。没有修改既有测试预期来掩盖回归。

## Build results

| Build | 结果 | 产物 |
| --- | --- | --- |
| Debug / iPhone 17 Pro Simulator | PASS | `/tmp/TasteMapDynamicTypeP1DerivedData/Build/Products/Debug-iphonesimulator/TasteMap.app` |
| Release / iPhone Simulator | PASS | `/tmp/TasteMapDynamicTypeP1ReleaseSim/Build/Products/Release-iphonesimulator/TasteMap.app` |
| Release / Generic iOS Device | PASS | `/tmp/TasteMapDynamicTypeP1ReleaseDevice/Build/Products/Release-iphoneos/TasteMap.app` |

Release 构建使用 `CODE_SIGNING_ALLOWED=NO` 做编译验收；未改 Signing、Capabilities 或任何 Production 配置。

## Release purity

Simulator 和 Generic Device 两个 Release `.app` 均通过以下检查：

- App bundle 内没有 `.xctest`、`TasteMapUITests` 或 `TasteMapTests` bundle。
- Release executable 不含 `TASTEMAP_VISUAL_QA_MODE`。
- Release executable 不含 `TASTEMAP_P4G_ROULETTE_UI_TEST`。
- Release executable 不含 `TASTEMAP_CORE_PARITY_INITIAL_TAB`。
- Release executable 不含 `TasteMapUITestFixtures` / `TasteMapVisualQAFixtures`。
- Release executable 不含 accessibility screenshot injection key、private UI fixture account marker。
- 没有引入 test login、Premium bypass、test credential、Debug-only runtime state 或 DEBUG marker。

用于截图的 rich state 继续位于既有 `#if DEBUG` fixture 中；本次没有向正式 runtime 添加测试分支。

## Design System Compliance

### Core UI

- 继续使用 `TasteMapCoreTheme` 的 brand、surface、border、text、shadow token。
- 没有新增颜色、字体样式或另一套 card / button 视觉语言。
- Default bottom navigation 的 88pt 构图、Capsule CTA、Tab icon/title 和选中态保持不变。

### Food & Dining visuals

- Discovery 餐厅 card 继续使用现有 `FoodDiningVisualIcon`、图片、rating badge 和 recommendation reason 视觉。
- Roulette 的主题颜色、转盘 segment、候选餐厅和结果视觉均未重新设计。
- 没有修改任何 food imagery、dish/photo presentation 或 dining asset。

### Canonical templates

- My Map 继续使用现有三 Tab + shared filter + Bottom Add CTA 模板；只在 Accessibility 下让 CTA/Tab 获得足够纵向空间。
- Discovery 继续保留“关注 / 为你推荐 / 同味之选 / 最新 / 趋势”五项结构和原顺序。
- Profile 继续保留既有 dashboard section 顺序；Accessibility 单列是响应式 reflow，不是重新组织产品 IA。
- Roulette 继续遵守“完整候选池参与随机、最多十个真实一一对应 segment”的既有契约。

### Duplicate / conflicting components

- 没有引入第二套 Bottom Navigation、Profile tile、Discovery card 或 Roulette 组件。
- 标准与 Accessibility 结构在同一 canonical component 内通过私有 layout content 复用，避免行为、label 和样式分叉。

### Default SwiftUI regressions

- 没有以默认 `TabView`、`List`、`Form`、系统蓝色 button 或默认 card 替换现有 Taste Map 组件。
- 系统能力仅用于正确的 SwiftUI layout：`ViewThatFits`、动态 HStack/VStack、flexible grid、ScrollView、intrinsic size 和 `contentShape`。

### Remaining design gaps

- 本专项范围内没有剩余 Design System gap。
- Accessibility 下的信息密度低于 Default 是有意且必要的可访问性 reflow，不构成视觉不一致。

## Changed files

- `ios/TasteMap/TasteMap/App/RootTabView.swift`
- `ios/TasteMap/TasteMap/Components/TasteMapBottomNavigation.swift`
- `ios/TasteMap/TasteMap/Features/Discovery/DiscoveryView.swift`
- `ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift`
- `ios/TasteMap/TasteMap/Features/Roulette/RestaurantRouletteView.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`
- `reports/full-layout-parity/dynamic-type-p1/`

## Remaining Accessibility risk

本次确认范围内没有新的 P0/P1。没有发现必须扩大任务范围才能关闭的 Accessibility failure。

仍需保留的一般性回归关注点是：未来新增更长的本地化文本、Profile dashboard 模块或 Roulette action 时，必须继续在 Accessibility Large / Extra Extra Large 下运行本专项 UI contract；这不是当前缺陷，也不阻塞本次 CLOSED。
