# 口味档案逐屏原型与最坑推荐来源 — 2026-09-07

## 交付状态

已落实到共享 React 分析页并安装固定模拟器的独立「味图测试」App。本轮不是全部 F01–F24 最终验收：F13 嵌入式 Native MapKit 足迹地图仍未接入；Native/SwiftUI 回退页面未迁移到新版模板，未改变正式路由归属。

依据用户提供的 `routes.json` 和 `TasteMap_逐屏可点击原型.html`，口味档案采用短首页、六个问题式主题、按条件下钻的详情与原始记录。原型数字不作为用户事实。最新明确要求「最坑推荐来源」已实现为「最合口味」的并列切换视角，独立来源分析也保留明确入口。

## 本轮实现

- F01 结论区分常吃与高分；食品视觉对应真实频率，最多四项分类和紧凑习惯信息。
- F02 直接进入偏好、消费、时间、足迹、饭搭子与来源、评分与记录六个主题，不再使用章节下拉。
- F03 筛选为草稿底部面板；取消不应用，日期与城市条件参与同一报告计算。
- 菜系、口味、实际消费、人均价位、时间、趋势、首次记录与回访、饭搭子、来源、评分、覆盖度均可进入对应的过滤记录。条件应用在同一条 Visit 上，不按展示文案猜条件。
- F22 计算说明为底部面板；F21 可继续打开正式用餐记录。保留阅读栈、视角和筛选状态。
- F24 口味名片采用最新原型的 9:16、1080×1920 输出。公开安全版本从公开记录重新计算，而不是只隐藏文字；不加入虚构二维码。
- 最坑来源要求至少 5 家已评分的归因餐厅；一家餐厅只采用首次归因体验。低于个人首次体验基线至少 1 分计入踩坑结果，展示分子、分母和对应餐厅，不评价推荐者本人。无合格样本时不强行排名。

## 验证结果

- 6 个针对性测试文件：117 项通过。
- Hybrid 分析路由定向测试：2 项通过。全文件仍有 6 项已有 Discovery 断言失败，不属于本轮修改，未报告全套通过。
- TypeScript 应用及 worker 检查、正式资源打包与 Release 资源纯净检查通过。
- `hybrid/scripts/check-taste-profile-explorer.mjs`：浏览器逐屏路径检查通过；375/402 宽、亮/暗主题首页无横向溢出；筛选取消与应用、图表下钻、来源低分视角、返回和 9:16 导出通过。浏览器榜单使用受控测试数据，并非真实用户结论。
- `testHybridTasteProfileQuestionRoutes`：固定 iPhone 17 Pro / iOS 26.5 模拟器 1 项通过。测试结果 `/tmp/tastemap-question-routes-v2-20260907.xcresult`。最坑榜在该原生测试夹具中为真实的样本不足状态；有数据榜单另由浏览器测试覆盖。
- 安装后的 QA App 人工打开「我的 → 我的口味档案 → 完整分析 → 饭搭子与来源」，确认新版 React 页面；进入餐厅再返回恢复共同经历页。

## 运行包证据

- 源码：`feature/hybrid-final-integration`，基准 HEAD `58bd556`，包含现有未提交改动；未提交或重置用户工作。
- 构建：`/tmp/tastemap-profile-status-derived/Build/Products/DebugQA-iphonesimulator/TasteMap.app`。
- 安装：模拟器 `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`，bundle `com.lafayette.tastemap.qa`。
- 已安装包：`/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/36E2098A-22F2-453F-87B4-BE8376BE2F41/TasteMap.app`。
- 正式 dist → staged public → built app → installed app：26 个文件逐字节一致，分别执行正式核验通过。
- 运行模式：React Hybrid，启动参数 `--tastemap-hybrid-development`，测试环境 `TASTEMAP_VISUAL_QA_MODE=rich`。夹具不是生产数据，未更新物理手机或发布生产版本。

## Design System Compliance

- Core UI：沿用共享控件、图标、ModalShell、导航与食品库；暖白/蓝灰为本次原型的模板组合，不另建 Browser/Capacitor 两套页面。
- Food & Dining：复用 FoodLibraryArtwork 与现有照片显示链路，图标对应分类；不生成无依据的餐厅照片，不将其他用户 UGC 自动导出。
- Canonical Page Templates：最新 HTML 的问题式阅读流程和 9:16 名片覆盖旧口味页约定；规则已同步至产品设计文档及分析/海报布局契约。
- 重复实现：其他四类分析仍沿用既有共享报告视图；Native/SwiftUI 回退仍是旧模板，明确作为未关闭差距，不宣称全端迁移完成。
- SwiftUI 默认样式：本轮未新增 SwiftUI 产品页面或默认控件替代设计系统。
- 未关闭差距：F13 嵌入式 MapKit、Native 回退模板、真实设备分享验收、全套逐屏像素级视觉验收；不能将当前版本标为全部原型完成。

## 预览

- `taste-profile-routes-2026-09-07/home.png`
- `taste-profile-routes-2026-09-07/questions.png`
- `taste-profile-routes-2026-09-07/source-pitfalls.png`
- `taste-profile-routes-2026-09-07/taste-card.png`
