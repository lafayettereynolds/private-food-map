# 地图与发现：紧凑筛选留白统一

## 原因与修正

地图的本地 `FilterSelect` 用字符估算 `ch` 宽度（最小 7ch），并受页面 86px 上限约束；发现使用系统 select 的固有宽度和另一份 94px 上限。外壳相似，但内部文字、隐藏选项和箭头占位不是同一套规则。

现在由 `TasteMapFilterSelect` 统一渲染图标、当前选中文字和展开箭头，宽度只由当前可见文字决定。原生 select 保留在整个点击区域上；不替换城市、排序或评分的数据与回调。长文字使用统一省略上限，下拉菜单仍展示完整选项。

- Map/List、Hybrid Discovery 城市／评分／排序，以及旧 Browser Discovery 评分／排序，接入同一组件。
- 地图消费、到访次数、饭搭子、菜系等同类紧凑下拉一起接入；全量筛选面板保持正常展开字段，不套紧凑布局。
- 原有页面局部宽度、间距、图标和深色外壳重复规则收回 shared CSS。发现页通用 `font: inherit` 不再覆盖筛选按钮字号。
- 统一两侧 9px、图标与文字／箭头之间 5px、图标 14px、箭头 10px。当前紧凑外观保留 44px 点击高度；短标签不再预留整块空白。
- 等长且相同的可见文字同宽；不是把“城市”和“综合推荐”等不同长度标签硬拉成等宽。
- 未改变搜索、城市归属、定位、地图坐标／聚合、消费、发现推荐算法、分页、数据权限、生产路由或真实用户记录。

## 同类入口盘点

| 入口 | 处理与验证范围 |
| --- | --- |
| React MyMapBrowsePage，地图及列表、三种 scope | 同一 MapFilterBar + shared select；真实模拟器比较城市／评分及列表共享布局 |
| React HybridDiscoveryPage 五板块，Browser / Capacitor | 城市、对应排序、对应公开／到访评分均 shared select；保留同一状态驱动工具栏和弹窗 |
| Browser CommunityPage 五板块 | 评分、排序采用 shared select；城市是可自由输入的 datalist 搜索，不擅自改成只能选已有城市的下拉，保留输入能力与共用外部间距 |
| Map FullFilterSheet、Discovery TasteMapFilterSheet | 展开表单语义，保留完整字段；不继承紧凑下拉的覆盖层 |
| Browser RestaurantFilters | 多行 FilterChoices／完整筛选，不是单行城市紧凑 select，无相同宽度算法 |
| Native MapHomeView / DiscoveryView rollback | 已共同使用 TasteMapFilterChip / TasteMapFilterChipLabel 和设计 tokens，源码未发现隐藏 select 选项／ch 宽度估算根因；未改 Native UI，也未以 Hybrid 截图冒充 Native 验收 |
| Native previews / Share Extension、HybridFilterBar 兼容 helper | previews 引用既有正式组件；分享扩展没有该城市工具栏；兼容 helper 无当前生产调用，不引入另一份新控件 |

## 验证

- 102 项 Vitest：地图及全局产品契约、Hybrid 页面、完整评分选项、shared select SSR；包含禁止恢复局部宽度、隐藏控件、字体被 host reset 覆盖的约束。
- 正式 stage 包含 `tsc -b`、worker typecheck、正式 Vite build 和资源相等校验。
- `hybrid/scripts/check-filter-chip-geometry.mjs`：实际浏览器布局比较 375 / 402 / 430 宽、浅色／深色、默认城市／杭州／长城市名称，城市、评分的内外宽度与间距相同。额外加入更长但未选中的 option 不改变宽度。
- 默认“城市”实测 72×44 CSS px，“不限评分”92×44 CSS px；两页相同。同一脚本验证筛选按钮字体、宽度、padding、gap，和原生 select 的焦点与选中文字同步。
- `hybrid/scripts/check-discovery-filter-interactions.mjs`：两个 React 入口 × 五板块，验证打开面板、城市＋评分真实过滤测试快照、排序、重开、重置、关闭，以及 Browser 已有高级筛选能力未丢失。
- 固定模拟器 `testHybridCompactFiltersShareGeometryAndKeepNativePickers`：地图→列表→发现，比较城市宽／高／横向位置、评分宽度，实际点选城市和 9 分以上，再清除。
- 同时回归 `testHybridDiscoveryFilterSheetsWorkAcrossEveryTab`，避免统一样式后筛选入口或系统选项失效。

### 验收过程中的修正与边界

初次 UI 测试停在 rich QA 默认“我的”页，未进入地图便查找城市控件，因而失败。最终测试明确点击底部地图入口。此前口头将该失败归因于透明控件不充分，已纠正；最终实现保留可见／可聚焦的原生元素，仅隐藏重复文字和系统箭头的绘制。

浏览器 headless 环境的键盘系统菜单选择不能作为已通过证据；脚本只声明焦点／select 状态同步，系统菜单操作以 iOS 实际点击测试为准。

截图为明确启用 rich QA 数据的 React Hybrid 页面：用于检验布局与交互，不代表线上真实发现内容或推荐完整性。Native MapKit 底图／标记仍由原有原生层渲染。

## 运行身份与交付

- 分支 `feature/hybrid-final-integration`，基础提交 `58bd556b8382734aeae1f08937ba649563682140`；保留此前未提交改动，未提交代码。
- QA `.app`：`/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`。
- 固定模拟器：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`，iPhone 17 Pro / iOS 26.5；bundle `com.lafayette.tastemap.qa`。
- 参数：`--tastemap-hybrid-development -AppleInterfaceStyle Light`；环境：`TASTEMAP_VISUAL_QA_MODE=rich`。
- 最终 UI 结果：`/tmp/tastemap-chip-accepted-ui.xcresult`，2 项通过、0 失败（97.344 秒）。[地图](map.png)、[列表](list.png)、[发现](discovery.png)截图已逐张核对；两页默认筛选与城市控件横向位置、城市与评分宽度一致。
- 最终安装包：`/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/ED4F1C4D-224F-4B2C-90D9-17114D45F640/TasteMap.app`。其 17 个 Web 文件与 dist、formal staged、QA build 逐字节一致；Release 编译通过，纯净扫描通过（39 app 文件、17 Web 文件）。
- 仅更新模拟器；未更新 iPhone，未部署后端，未发布应用。

## Design System Compliance

- Core UI：组件与 spacing/icon/control tokens 由 shared 层统一；保持原生菜单、完整 option/a11y 标签、44px 命中区，增加共同的键盘焦点框；深浅色 selected 状态一致。
- Food & Dining：不更换照片、分类图、评分颜色策略、地图标记或餐厅视觉来源。
- Canonical Page Templates：保留标题、tabs、横向滚动筛选、地图／卡片、底部导航与 CTA；不以更换模板解决留白。
- 重复组件：移除本次同语义页面级宽度算法和样式分叉；不同数据来源只保留 option/value/onChange 适配。可编辑城市输入与展开表单的不同语义明确保留。
- SwiftUI：没有引入默认 SwiftUI 替代界面，没有变更 Native-primary／rollback 归属。
- 剩余边界：独立 Native rollback 仅源码盘点；最终视觉喜好仍由用户查看确认。本报告不延伸为搜索定位、真实 feed、推荐算法等历史任务全部完成的声明。
