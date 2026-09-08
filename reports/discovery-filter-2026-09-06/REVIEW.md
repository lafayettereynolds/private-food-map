# 发现筛选入口与同类无效操作修正

## 原因与处理

用户截图里的 Hybrid `筛选` 不是触摸事件丢失：回调只切换了 `tm-discovery-filter-summary`，其内容只有说明和重置，没有可操作的筛选字段。五个发现板块共用这个错误实现。

同类盘点还发现旧 Browser `CommunityPage` 的筛选面板仅在 `for_you` 渲染，其他四个板块仍显示触发按钮；非 `for_you` 的评分和排序状态没有用于结果；会员高级筛选按钮在解锁时没有实际操作。

已处理：

- 两套 React 入口共用 `TasteMapFilterSheet`，复用 `ModalShell` 和已有表单／弹窗操作样式，不再以说明条冒充面板。
- 五个板块均可打开城市、排序、最低评分；评分提供不限、1–10 整数和既有 7.5 选项。保留公开评分与具体到访评分的区别。
- Browser 非推荐板块的评分与评分排序接入实际可见结果。城市同时请求服务端，并在当前快照按城市规范化校验，避免旧异步结果或混合城市内容通过新条件。
- Browser 已有推荐距离能力保留；高级推荐来源、适合场景、饭搭子筛选使用已授权返回的 Visit 字段。未解锁仍进入原 Premium 流程，不绕过权限；数据缺失不造记录。
- 修改立即更新当前查询；关闭／查看结果不清空选择，重新打开保留，重置清除面板条件。工具栏与面板共用状态，没有第二套查询。
- 页头、五个 tabs、卡片、地图／位置、消费、评论和真实数据读取架构不在本次改造范围。没有切换生产路由或发布线上变更。

## 全局消费者盘点

| 消费者 | 检查结果 |
| --- | --- |
| HybridDiscoveryPage，Browser / Capacitor 五板块 | 同根因，已统一修正；两种运行环境有交互证据 |
| Browser CommunityPage 五板块 | 面板 tab 限制、未应用的评分／排序、会员按钮空操作，已修正 |
| MyMapBrowsePage 的 MapFilterBar / FullFilterSheet | 已连接真实全量筛选和 typed query，无同类说明条替代或空回调；本次不重绘地图筛选 |
| Browser RestaurantFilters | 已有真实字段变更回调，不是说明条假面板 |
| Native DiscoveryContentView / DiscoveryFilterSheet | 已有 filterFocus → sheet → filters Binding，并有重置／完成；未发现本次同根因，不改变 Native 既有功能范围 |
| Native MapHomeView / PersonalRestaurantFilterView | 已有同一 filterFocus 与有效 binding，未发现本次同根因 |
| Native Community / previews / Share Extension | 未发现另一份同语义失效触发器；previews 引用现有正式 view，分享扩展没有发现筛选入口 |
| HybridFilterBar compatibility helper | 静态 span 标题，无冒充动作的回调；仓库无生产调用方，与本次按钮不同语义 |

## 验证与边界

- `hybrid/scripts/check-discovery-filter-interactions.mjs`：隔离浏览器测试，两套入口 × 五板块逐项验证打开、城市＋评分组合结果、排序、重开、重置、关闭，以及 Browser 高级来源＋场景＋饭搭子同时匹配同一 Visit 的过滤。不是只断言按钮存在。
- 80 项 Vitest：全局产品约束、Hybrid 页面、完整评分选项、筛选解析服务；TypeScript build 通过。
- 固定模拟器测试 `testHybridDiscoveryFilterSheetsWorkAcrossEveryTab`：五板块都打开面板，真实点击系统评分选项，关闭后检查筛选计数，再重开、重置。初次测试错误地将 `aria-haspopup=dialog` 的 WKWebView 元素按 Button 查找；实际辅助功能类型为 Other。依据运行层级修正测试定位后通过，并非产品点击失败。
- 浏览器通过模块响应拦截提供隔离数据，模拟器为显式 rich QA。测试数据仅证明交互和筛选计算，不证明线上发现内容完整性、推荐真实性或实时分页。
- Native rollback 和地图筛选在本次做了源码入口／binding 盘点，没有把 Hybrid 截图冒充这些独立页面的运行证据。

## 运行身份与资源

- 分支 `feature/hybrid-final-integration`，基础提交 `58bd556b8382734aeae1f08937ba649563682140`，保留用户既有工作区改动，未提交。
- QA 构建 `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`。
- 固定模拟器 `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`；bundle `com.lafayette.tastemap.qa`。
- React Hybrid，`--tastemap-hybrid-development -AppleInterfaceStyle Light`，`TASTEMAP_VISUAL_QA_MODE=rich`，发现五板块。
- 正式资源按 `hybrid:stage:formal → dist / staged / built / installed` 验证。最终结果与截图在本目录留存。
- 最终安装包 `.../Containers/Bundle/Application/4B8ACA27-BA51-4A49-ACBC-5C4357E7353F/TasteMap.app`；与 dist / staged 各 17 文件逐字节一致。最终模拟器结果 `/tmp/tastemap-filter-final-ui.xcresult` 通过，五板块及停留面板截图已保存并核对。最终 Release 编译和纯净扫描通过：39 app 文件、17 Web 文件。
- 未更新真实 iPhone，未改真实消费／到访记录，未请求用户位置，未部署服务器。

## Design System Compliance

- Core UI：复用 shared FilterBar、ModalShell、modal-actions 和字段语法；输入至少 16px，按钮／关闭触控使用既有 44px token。清晰层级、明确关闭和查看结果。
- Food & Dining：不改餐厅图像来源、卡片照片、地图标记或评分视觉。
- Canonical Page Templates：保留发现页标题、五个 tabs、单行工具栏与卡片顺序；全量筛选是独立弹窗，不插入一条说明挤动内容。
- 重复组件：两个发现数据入口复用一个筛选面板框架，各自保留已有数据适配边界；未创建 Capacitor 专属面板或另一套算法。
- SwiftUI：没有引入新的默认 SwiftUI 页面或替代 Native 渲染。Native 同义入口经源码盘点无本次根因，未扩大其筛选能力。
- 剩余边界：独立 Native 筛选未采集本次新截图；线上 feed 完整性和真机验收仍属单独任务。用户最终视觉接受不由自动测试代替。

持久规则已写入 `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` 的 Filters。
