# Taste Map｜Lafayette 最新视觉审批执行矩阵

生成日期：2026-09-02

正式产品分支：`fix/product-ux-correction-8-tasks`

审批包：`TasteMap-Lafayette-Visual-Approval.zip`
审批包 `approval.json` SHA-256：`0a36df17c34811abb7a46fbfe589c1b5d0c0237666705acbbdc78490a9772604`

## 1. 执行边界

这份矩阵把 Lafayette 最新正式视觉审批包转换为可执行约束。它不是新一轮自动审计，也不授权 Codex 改动任何未明确选择的区域。

- `KEEP CURRENT`：冻结当前正式实现。
- `KEEP LEGACY`：以真实 Legacy Web 的布局、信息架构和交互为视觉基础；保留当前数据、认证、同步、社交、Premium、分享和安全能力。
- `KEEP FUSE`：冻结 Lafayette 已看到并选择的融合实现。
- `NEEDS REDESIGN`：只允许在独立 DEBUG 候选分支制作新候选；未获 Lafayette 再次批准前不得进入正式产品分支。
- 空白选择：不得自动推断、不得修改、不得标记通过。
- `frozen = true`：后续候选版本不得连带修改。

统计：14 个页面、122 个区域；103 个区域已明确冻结，18 个区域待重设计，1 个区域保持未选择。

## 2. 页面级执行矩阵

| 页面 | 页面方向 | 已冻结区域 | 可修改区域 | 正式分支动作 | 候选分支动作 |
| --- | --- | ---: | ---: | --- | --- |
| 我的地图 / 我的列表 | Legacy | 10 | 0 | 只落实冻结备注与已批准 Legacy/FUSE 细节；不改业务状态 | 无 |
| 发现 | Legacy | 11 | 0 | 保持已批准的五 Tab、筛选与 Legacy 内容卡结构 | 无 |
| 添加餐厅 / Nearby | Legacy | 10 | 0 | 保持 Legacy 搜索/Nearby/手动添加流程及 Current 分享导入 | 无 |
| Restaurant Detail | Legacy | 7 | 0 | 保持全局唯一主体与 Legacy 区域顺序 | 无 |
| Roulette | Legacy | 10 | 0 | 保持 Legacy 轮盘构图和当前正确数据能力 | 无 |
| 我的页面 | FUSE | 7 | 1 | 冻结 7 区；不得修改核心入口 | 仅重做“核心入口”候选 |
| 到访记录 | FUSE | 8 | 0 | 保持 Legacy 布局；核对文字评分说明与顶部总评分 | 无 |
| 菜品与照片 | Legacy | 8 | 0 | 不改已确认布局与照片安全边界 | 无 |
| 公开主页 / 社交 | Legacy | 7 | 1 空白 | 只落实已冻结区域明确备注；Header 保持原样 | 无；Header 等 Lafayette 选择 |
| 我的食单 / 公开食单 | Legacy | 8 | 0 | 保持 Legacy 构图及当前分享/权限能力 | 无 |
| 数据分析 × 4 | Needs redesign | 0 | 8 | 不修改正式页面 | 重新制作真实高保真候选 |
| 五类分享海报 | Needs redesign | 0 | 8 | 不修改正式 renderer | 重新制作五类真实 9:16 候选 |
| Premium 会员页 | Legacy | 7 | 1 | 冻结 Paywall 其余 7 区 | 仅重做汉堡候选 |
| 设置 / 数据 | Current | 10 | 0 | 全页冻结，不修改 | 无 |

## 3. 逐区锁定清单

### 3.1 我的地图 / 我的列表

- `KEEP CURRENT`：顶部标题与地图/列表切换。标题与图标作为整体居中；图标更小、位于标题右侧。
- `KEEP FUSE`：去过/想吃/推荐、筛选栏、选中餐厅与预览、添加餐厅按钮、地图/列表状态保持、空白/加载/错误。
- `KEEP LEGACY`：餐厅标记与重叠层级、用户位置、列表条目。
- 必须落实的备注：Restaurant Marker 恢复评分色；餐厅头像优先真实 Restaurant 图片，不得用装饰图冒充可取得的商户图片。

### 3.2 发现

- `KEEP FUSE`：居中标题、五个一级 Tab、筛选栏。
- `KEEP LEGACY`：动态卡片、用户/时间、餐厅图片/信息、到访评分、点赞/评论/更多、餐厅操作、同味内容、空白/加载/错误。
- 语义锁定：Activity 显示该次 Visit rating，不以 Restaurant aggregate rating 替代。

### 3.3 添加餐厅 / Nearby

- `KEEP CURRENT`：分享导入。
- `KEEP LEGACY`：顶部、搜索、附近餐厅、手动添加、搜索结果、附近结果、餐厅预览、想去/记录到访操作、Restaurant Detail 过渡。
- 当前数据保护：fresh CLLocation、stale rejection、accuracy、provider identity、dedupe 与状态确认不得倒退。

### 3.4 Restaurant Detail

- 七区全部 `KEEP LEGACY`：Hero、名称与操作、基础信息、评分参考、用户实拍、到访概览、下游内容。
- 当前能力保护：所有入口继续使用同一 canonical detail body；`entrySource` 不得改变主体 UI。

### 3.5 Roulette

- 十区全部 `KEEP LEGACY`：顶部、候选概览、轮盘几何、指针与中心、餐厅分区、空白分区、候选管理、抽签结果、餐厅图片、空白/错误。
- 当前能力保护：最多 10 个候选、真实 Restaurant image policy、状态和抽签逻辑不得倒退。

### 3.6 我的页面

- `KEEP LEGACY`：顶部身份区、主统计、我的食单、设置。
- `KEEP FUSE`：关注数据、回味、洞察。
- `NEEDS REDESIGN`：核心入口；原因是两侧视觉不对称、不协调。
- 冻结备注：人物名字下显示“关注 / 粉丝”；“总消费”与“想去”同一主统计组；顶部不新增额外“我的”；Add Friend/Settings 使用 Legacy 顶部关系；Premium 使用已确认的历史汉堡语义。

### 3.7 到访记录

- 八区全部 `KEEP LEGACY`：顶部、餐厅信息、用餐体验、评分、菜品与照片入口、用餐情境、备注、保存按钮。
- 必须核对：餐厅总评分置于评分区域最上方；详细评分继续带清晰文字维度说明。

### 3.8 菜品与照片

- 八区全部 `KEEP LEGACY`：顶部、照片叙事、上传状态、菜品列表、添加/编辑、重试/错误、本地原图安全、删除边界。
- 当前能力保护：不得删除唯一原图、业务元数据或已同步关系。

### 3.9 公开主页 / 社交

- 未选择：`Header`。备注虽写“第二轮已确认”，但 machine choice 为空；本轮不修改也不自动冻结。
- `KEEP LEGACY`：关注数据、主要操作、内容分类、餐厅记录、动态、公开食单、举报/拉黑。
- 必须落实的冻结备注：用户可见术语使用“粉丝”，不再显示“被关注”；Restaurant Evidence 中头像使用与“我的”一致的居中关系；内容入口明确为“动态 / 食单”。

### 3.10 我的食单 / 公开食单

- 八区全部 `KEEP LEGACY`：顶部、封面、可见性、排名、餐厅条目、成员操作、分享、空白/长文本。
- 当前能力保护：公开/私密权限、真实 Restaurant image、分享与成员关系不得倒退。

### 3.11 数据分析 × 4

- 八区全部 `NEEDS REDESIGN`：顶部、核心食物主视觉、周边分析节点、核心洞察、TOP 3、分布、代表餐厅图片、底部品牌区。
- 正式页面保持不动；仅在 DEBUG 候选分支制作真实候选。

### 3.12 五类分享海报

- 八区全部 `NEEDS REDESIGN`：顶部、Food Hero、核心结论、数据标注、代表餐厅图片、品牌底部、二维码/隐私、9:16 构图。
- 正式 renderer 保持不动；候选必须是实际 SwiftUI 9:16 renderer 输出，不使用 HTML/拼接/AI 效果图冒充。

### 3.13 Premium 会员页

- `KEEP FUSE`：顶部、权益层级、商品信息、购买按钮、恢复购买、法律信息、Free/Premium 状态。
- `NEEDS REDESIGN`：汉堡。只重做这一视觉元素；旧版会员标识作为参考，不改变 StoreKit entitlement 或购买流程。

### 3.14 设置 / 数据

- 十区全部 `KEEP CURRENT`：顶部、Account、Data & Backup、Sync、Privacy、Permissions、Storage、Premium、Help、About。
- 全页冻结；本轮不得品牌化重排。

## 4. Analytics 高保真参考拆解

参考图片：`references/analytics-compositions/01-clipboard-1788307552152-1.png`。审批包元数据虽不是最终方向标记，但 Lafayette 最新文字指令明确将其升级为 **HIGH-FIDELITY VISUAL / COMPOSITION SOURCE OF TRUTH**。

### 4.1 构图合同

1. 顶部左侧是编辑感标题与短说明，不使用普通居中导航大标题替代。
2. 中央 Food Hero 是第一视觉焦点，占主要宽度但保留呼吸空间。
3. 菜系节点环绕主视觉，以真实占比驱动；细虚线连接，位置稳定。
4. 左侧 TOP 3 使用排名、真实菜品/餐厅图和次数/评分。
5. 右侧是纸张/票据式数据总览与近期洞察，形成非对称平衡。
6. 中下区域分布为口味偏好、消费类型、人均区间、城市足迹、饭搭子、用餐时间等不同信息图形态。
7. 微暖白底、细边框、纸张阴影、少量食材色；不得退化为同宽卡片纵向堆叠。
8. 小图标必须是同一 Food & Dining illustration family，且数据型图形只能表达真实数据。
9. Restaurant imagery 必须通过 canonical Restaurant image renderer；有真实图时禁止用 FoodDining fallback 覆盖。
10. iPhone 纵向需要重排但不得改变上述视觉层级；允许使用可读的分段画布或横向信息带，不允许将所有模块翻译成普通 `VStack + Card`。

### 4.2 四类页面语义合同

- 我的口味档案：Food Hero + 菜系节点为中心，展示偏好、TOP 3、消费、城市、饭搭子与时间。
- 最佳饭搭子：双人餐桌/餐具作为语义 Hero，围绕共同到访、评分一致度、代表餐厅、时间与消费展开。
- 谁最会种草：菜单/小票/来源链作为语义 Hero，围绕命中率、来源排行、代表餐厅、消费与评分结果展开。
- 本月回顾 / 年度回顾：时间轨迹作为构图骨架，保留 Food Hero、代表餐厅、消费、城市、伙伴和变化结论；月/年不得只是换标题。

## 5. 五类海报高保真合同

参考图片：`references/poster-family/02-clipboard-1788307684319-1.png`（与 Analytics 参考内容相同，只用于定义视觉家族，不等于可直接裁切成海报）。

- 五类：我的口味档案、最佳饭搭子、谁最会种草、本月回顾、年度回顾。
- 每一类必须有不同的主叙事骨架和真实数据结论，但共享暖白纸张、Food/Dining illustration、编辑排版、连接线、品牌底部。
- 真实输出比例 9:16；安全区、可读字号、SharePosterBrandFooter、二维码/隐私按正式规则处理。
- 不得把同一个画布仅替换标题和几项数字。
- 候选图必须来自真实 SwiftUI renderer；正式产品实现保持不变，直到 Lafayette 明确批准。

## 6. Git 与分支策略

- 正式分支：只允许实现已冻结且备注明确、不会改变审批方向的收口；每个修改必须有针对性 regression。
- 候选分支：`preview/fuse-visual-candidates`，仅 DEBUG 可达；承载 Profile Core Entries、Analytics、Poster、Premium Hamburger 新候选。
- 候选标识（V1/V2/V3、Frozen/Pending、修改范围）只存在 DEBUG 候选画廊；同时生成无候选标识的 Clean Preview。
- 候选不得自动合并、不得自动更新为 `APPROVED FINAL`。
- Production、App Store、Signing、Capabilities、SwiftData schema、Sync、App Icon 均不在本轮范围。

## 7. 完成判定

本轮只有同时满足以下条件才可报告完成：

1. 所有已冻结区域未被候选版本意外改变。
2. 18 个重设计区域产生真实可运行候选和截图；若某项客观无法完成，必须明确列出，不得伪报。
3. 公开主页 Header 保持未选择状态。
4. Analytics 候选逐项通过 Reference Decomposition / Layout Contract 对比。
5. 五类海报分别输出真实 9:16 候选。
6. 正式分支和候选分支边界清楚，正式产品没有 DEBUG 候选标签。
7. Release build 不包含候选入口或 bypass。
8. 最终只把新候选交回 Lafayette 审批，不替 Lafayette 自动选择。
