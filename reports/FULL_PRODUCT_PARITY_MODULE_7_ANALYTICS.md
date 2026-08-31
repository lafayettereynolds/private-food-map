# Taste Map｜Full Product Parity Module 7：Analytics / 数据分析与分享海报

验收日期：2026-08-31

执行分支：`fix/full-product-parity-restoration`

模块目标：恢复已经确认的 Analysis Visual Language，保留五类分析的真实统计口径，并让页面与独立 9:16 分享海报重新使用同一套 Food & Dining 视觉词汇。

## 1. Step A｜数据语义与既有实现审计

本模块没有重写 analyzer。仓库中的 P4 实现已经具备成熟且可测试的数据语义：

| 分析 | 真实数据来源 | 已确认的关键语义 |
| --- | --- | --- |
| 我的口味档案 | 当前账户范围内的 Restaurant、Visit、Dish、VisitDish、PhotoAsset、Companion、RecommendationSource | 菜系排行、实际消费、场景、来源、饭搭子、评分风格、回头率、关键词、时间与代表餐厅；`nil` 评分/消费不伪装成 0 |
| 最佳饭搭子 | Visit 的 companion IDs/names、关联餐厅/菜品/照片与可见社交资料 | 多饭搭子到访分别计入；重名不合并身份；私人备注不进入海报；共同餐厅和建议来自真实关联 |
| 谁最会种草 | Visit 的 recommendation source identity 与首次带来的 distinct Restaurant | 同一家店重复到访不重复放大来源；“最靠谱/最坑”必须达到样本门槛；Want To Go 不伪造来源 |
| 本月回顾 | 选定自然月内的 Visit 与其 Restaurant/Dish/Photo/Companion/Source | 到访、餐厅、新店、实际消费、最喜欢/最常去、饭搭子、来源与口味变化均按自然月计算 |
| 年度回顾 | 选定自然年内的同一数据投影 | 全年统计、月度高光、味觉轨迹、代表餐厅和关键词只在证据充分时出现 |

五类输入继续先经过 `ProfileOwnedContentScope` 与全局 Restaurant identity projection；本模块没有修改 SwiftData、API、Worker、D1、认证或 SyncEngine。

## 2. 历史设计恢复依据

优先复用了仓库历史分支 `codex/taste-analysis-visuals` 中已经认可的实现，而不是设计第三套：

- 历史实现 commit：`e855f6f Add native taste profile analysis visuals`
- 中心 Food Hero + 四周 callout + connector web；
- 暖白 Analysis canvas 与灰蓝品牌色；
- `FoodHeroJapanese`、`FoodHeroHotpotGrill`、`FoodHeroChinese`、`FoodHeroWestern`、`FoodHeroCafe`、`FoodHeroMixed` 六组已认可图像资产；
- 页面阅读布局和独立 9:16 海报布局共享 presentation model，但不强制共用同一排版。

当前五类 Analysis 已在此基础上扩展完成，因此本模块只修复视觉回退，没有推倒重建。

## 3. Step B｜视觉恢复

### 3.1 Analysis Theme 与 Core App Theme 分层

恢复后的 Analysis light palette：

| Token | Value |
| --- | --- |
| Brand | `#506C8C` |
| Brand Deep | `#344F69` |
| Canvas | `#FBFAF7` |
| Card | `#FFFFFF` |
| Ink | `#24313C` |
| Secondary Ink | `#667179` |
| Hairline | `#E2E5E2` |

Analysis 不再直接把 Core App page/surface/text tokens 当作自己的全部视觉。Core App 继续冷白灰蓝；Analysis / Poster 使用轻暖白、真实食物主视觉和少量食材色。Dark Mode 保留动态语义颜色，导出的海报继续固定 Light Mode，确保分享图片一致。

### 3.2 中心 Food Hero

- 真实 Dish / Restaurant 照片优先；
- 无可用照片时，按真实 cuisine / dish label 选择日料、火锅烧烤、中餐、西餐、咖啡或多元拼盘；
- 推荐来源没有足够 cuisine 证据时使用 `FoodHeroMixed` 作为 **Decorative** 中心餐桌，不宣称它是用户偏好；
- 数据不足时明确显示形成中，不生成假餐厅、假评分或假照片。

### 3.3 Food & Dining Visual Library

新增唯一可复用的 `FoodDiningVisualLibrary` 与 `FoodDiningVisualIcon`：

- 分类：food、drink、tableware、receipt、menu、takeaway、shared meal、restaurant、rating、calendar、repeat visit、time、photo、tag、location、trend、discovery、generic dining；
- 使用方式显式区分 `decorative` 与 `dataLinked`；
- data-linked 先按稳定 semantic ID 选择图标，再兼容旧 presentation symbol；
- 旧 analyzer 内的 emoji presentation 值可以保持兼容，但正式 UI 不再直接渲染系统 Emoji；
- 同一个语义稳定映射，不会因 View re-render 随机变化；
- VoiceOver 中 Decorative 隐藏，Data-linked 使用明确语义标签。

### 3.4 页面与海报

- 我的口味档案：中心食物、四周四个关键 callout、九类分析故事、消费小票、代表餐厅图文和海报保持；
- 最佳饭搭子：双人餐桌、共同到访/餐厅/食物/最近时间、关系画像、代表餐厅和下次吃什么保持；
- 谁最会种草：来源小票流向餐桌、“最常使用/最靠谱/最坑推荐来源”、证据餐厅和海报保持；
- 本月回顾：照片/食物 Hero、月度统计、餐厅故事、饭搭子/来源、口味变化和海报保持；
- 年度回顾：年度拼贴、统计、月度高光、味觉轨迹、关键词、代表餐厅和海报保持；
- 空图片、空关键词、消费、共享餐桌、餐厅证据等正式组件统一改用 Food & Dining vector language，不再散落系统 Emoji。

## 4. Before / After 证据

| 类型 | Before | After |
| --- | --- | --- |
| 我的口味档案页面 | [before](full-product-parity-assets/ios-taste-profile-before-module-7.png) | [after](full-product-parity-assets/ios-taste-profile-after-module-7.png) |
| 口味档案 9:16 海报 | [before](full-product-parity-assets/ios-taste-profile-poster-before-module-7.png) | [after](full-product-parity-assets/ios-taste-profile-poster-after-module-7.png) |
| 最佳饭搭子页面 | [before](full-product-parity-assets/ios-companion-before-module-7.png) | [after](full-product-parity-assets/ios-companion-after-module-7.png) |
| 最佳饭搭子海报 | [before](full-product-parity-assets/ios-companion-poster-before-module-7.png) | [after](full-product-parity-assets/ios-companion-poster-after-module-7.png) |
| 谁最会种草页面 | [before](full-product-parity-assets/ios-source-before-module-7.png) | [after](full-product-parity-assets/ios-source-after-module-7.png) |
| 谁最会种草海报 | [before](full-product-parity-assets/ios-source-poster-before-module-7.png) | [after](full-product-parity-assets/ios-source-poster-after-module-7.png) |
| 本月回顾页面 | [before](full-product-parity-assets/ios-monthly-before-module-7.png) | [after](full-product-parity-assets/ios-monthly-after-module-7.png) |
| 本月回顾海报 | [before](full-product-parity-assets/ios-monthly-poster-before-module-7.png) | [after](full-product-parity-assets/ios-monthly-poster-after-module-7.png) |
| 年度回顾页面 | [before](full-product-parity-assets/ios-annual-before-module-7.png) | [after](full-product-parity-assets/ios-annual-after-module-7.png) |
| 年度回顾海报 | [before](full-product-parity-assets/ios-annual-poster-before-module-7.png) | [after](full-product-parity-assets/ios-annual-poster-after-module-7.png) |

## 5. 自动化验收

### Unit / rendering tests

- `AnalysisVisualParityTests`
- `P4ATasteProfileTests`
- `P4BDiningCompanionTests`
- `P4CRecommendationSourceTests`
- `P4DMonthlyRecapTests`
- `P4EAnnualRecapTests`
- `P4IProductHardeningTests`

覆盖 Analysis/Core palette 分层、Food/Dining semantic mapping、六组 Food Hero assets、nullable semantics、owner isolation、global Restaurant identity、真实照片 fallback、数据门槛、determinism、performance、9:16 rendering 与临时分享文件生命周期。

### UI tests

五条页面 → 独立 poster → system share → 返回 → 历史周期/实时刷新核心路径：

1. `testP4ATasteProfilePageAndIndependentPoster`
2. `testP4BDiningCompanionAnalysisRefreshAndPoster`
3. `testP4CRecommendationSourceAnalysisEvidencePosterAndRefresh`
4. `testP4DMonthlyRecapHistoryRestaurantPosterShareAndRefresh`
5. `testP4EAnnualRecapHistoryRestaurantJourneyPosterShareAndRefresh`

DEBUG fixture 同时修复了两类测试合同错误：新增月度/年度 Visit 显式使用当前 fixture 用户 owner，避免被正确的 current-user scope 排除；插入后再使用同一 `ProfileOwnedContentScope` 抓取输入并完成 analyzer，随后才显示“已刷新”。因此测试验证的是实际统计值变化，不只是提示文案。该入口只存在于 DEBUG，不进入 Release，也不接触真实用户数据。

### Build

- Debug Simulator build：PASS
- Release Simulator build：PASS
- `git diff --check`：PASS

## 6. 安全边界

- 用户可见正式名称：`最佳饭搭子`、`谁最会种草`，没有回退旧名称；
- SwiftData schema：未修改；
- analyzer 业务口径：未修改；
- API / Worker / D1 / migration：未修改；
- Auth / SyncEngine：未修改；
- Production：未访问；
- App Icon：未修改；
- Google Drive、Restore、Legacy Claim、废弃 Visit 字段：未恢复。

## 7. Module 7 结论

**PASS**。Analytics 不再只是“有数据、有图表”：五类页面保留中心食物与故事化分析，五类独立海报保留可传播的 9:16 排版，统计语义继续来自真实 owner-scoped 数据；Analysis Theme 与 Core App Theme 已重新分层，正式图标也进入统一 Food & Dining visual vocabulary。
