const R2_LEGACY = "../legacy-reference-screenshots/";
const R2_ATLAS = "../final-atlas/";
const R2_FORMAL = "round-2/formal/";
const R2_CANDIDATE = "round-2/candidates/";

function r2v(kind, title, src, caption) { return { kind, title, src, caption }; }

window.round2Decisions = [
  {
    id: "profile-density", title: "Profile｜FUSE Candidate V2", shortTitle: "Profile", direction: "FUSE", directionLocked: true,
    candidateTitle: "FUSE CANDIDATE V2 — NOT YET APPROVED", candidateVersion: "FUSE V2",
    summary: "Header 与 Settings 严格继承 Legacy 并保持冻结；其余六个区域仍待 Lafayette 逐区审批。",
    visuals: [
      r2v("CURRENT iOS", "当前 Premium Profile", R2_ATLAS + "final-atlas-profile-premium-analytics.png", "当前正式实现，仅作为对照。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy Profile Dashboard", R2_LEGACY + "legacy-fb127e9-profile-dashboard-1280x720.png", "fb127e9 · 真实历史 Dashboard；Header 与 Settings 的冻结来源。"),
      r2v("APPROVED HISTORICAL REFERENCE", "历史 Profile Reference", "../../full-product-parity-assets/web-profile-before.jpg", "已保存的历史 Web reference。")
    ],
    fuseVisuals: [r2v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Profile FUSE V2", R2_CANDIDATE + "profile-fuse-v2.png", "独立 preview branch 的 DEBUG SwiftUI 实现；Header/Settings 不再改动。")],
    legacyBase: ["Legacy compact Dashboard topology。", "Header 与 Settings 已由 Lafayette 标记 KEEP LEGACY / Frozen YES。"],
    currentAdditions: ["Premium、关注 / 被关注、去过 / 想去 / 总消费。", "今天吃什么、我的口味档案、三类回味、食单、最佳饭搭子、谁最会种草。", "Current Social、Sharing、Settings 与安全边界。"],
    proposedFinal: ["冻结 Header → 社交关系 → 核心统计 → 核心入口 → 回味 → 食单 → 洞察 → 冻结 Settings。", "只继续迭代六个 Pending 区域。"],
    recommendation: "只审批六个 Pending 区域；Header 与 Settings 已冻结，不应在 V3 中重做。",
    regions: ["Header", "Social Metrics", "Main Statistics", "Core Entries", "Memory / 回味", "Lists", "Insights", "Settings"]
  },
  {
    id: "visit-editor-density", title: "Visit Editor｜FUSE Candidate", shortTitle: "Visit Editor", direction: "FUSE", directionLocked: true,
    candidateTitle: "FUSE CANDIDATE — NOT YET APPROVED", candidateVersion: "FUSE V1",
    summary: "融合 Legacy 单次用餐叙事顺序与 Current 完整 Visit 合同；全部区域仍是 Pending。",
    visuals: [
      r2v("CURRENT iOS", "Visit 核心表单", R2_ATLAS + "final-atlas-visit-core-form.png", "Current 核心表单。"),
      r2v("CURRENT iOS", "Visit Rich State", R2_ATLAS + "final-atlas-visit-rich-photo-dish-context.png", "Current 菜品、照片与上下文。"),
      r2v("CURRENT iOS", "多维评分", R2_ATLAS + "final-atlas-visit-detailed-ratings.png", "Current 多维评分。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy Visit Editor", R2_LEGACY + "legacy-fb127e9-visit-editor-1280x720.png", "fb127e9 · Restaurant → repeat visit。")
    ],
    fuseVisuals: [r2v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Visit Editor FUSE V1", R2_CANDIDATE + "visit-editor-fuse-v1.png", "Legacy 日记式连续结构 + Current optional、多维评分与媒体合同。")],
    legacyBase: ["一次到访的自然叙事顺序与紧凑日记式分组。", "餐厅上下文、评分、内容和备注保持视觉连续。"],
    currentAdditions: ["nil/optional、多维评分、消费、饭搭子、推荐来源与正式用餐上下文。", "SwiftData local-first、离线队列、Dish/Photo 生命周期；六个废弃字段继续 RETIRE。"],
    proposedFinal: ["按 Legacy 叙事组织 Current 完整字段。", "复杂媒体/上下文渐进展开，唯一真实保存逻辑保持不变。"],
    recommendation: "全部区域仍待审批；Candidate 不能标记为 Final。",
    regions: ["Header", "Restaurant Context", "Core Experience", "Ratings", "Dish / Photo Entry", "Dining Context", "Notes", "Save CTA"]
  },
  {
    id: "dish-photo-composition", title: "Dish / Photo｜Legacy-based Final Candidate", shortTitle: "Dish / Photo", direction: "Legacy", directionLocked: true,
    candidateTitle: "LAFAYETTE DIRECTION: LEGACY · FINAL CANDIDATE", candidateVersion: "Legacy Final Candidate",
    summary: "已按 LEGACY direction 进入正式实现；业务模型、同步、重试与图片安全边界保持 Current。",
    visuals: [
      r2v("CURRENT iOS", "Current Dish / Photo", R2_ATLAS + "final-atlas-visit-rich-photo-dish-context.png", "改造前 manager-style 状态。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy Dish / Photo Manager", R2_LEGACY + "legacy-fb127e9-visit-dish-photo-manager-1280x720.png", "fb127e9 · Visit Editor lower section。")
    ],
    fuseVisuals: [r2v("FINAL iOS — REAL IMPLEMENTATION", "Dish / Photo Legacy-based Final Candidate", R2_FORMAL + "dish-photo-legacy-final-candidate.png", "正式分支真实 SwiftUI：菜品/照片作为同一次用餐故事。")],
    legacyBase: ["菜品与实拍属于一次用餐故事。", "图文关系优先于抽象工具面板。"],
    currentAdditions: ["Dish / VisitDish / PhotoAsset、local original、上传下载、重试、复用与独立删除。", "Restaurant 真实图片优先与不可丢失照片边界。"],
    proposedFinal: ["Legacy 餐饮故事骨架内继续暴露 Current 同步、失败、重试与删除状态。"],
    recommendation: "方向已确定为 Legacy；请核对真实 Final Candidate 是否忠实执行。",
    regions: ["Header", "Photo Story", "Upload Status", "Dish List", "Add / Edit Actions", "Retry / Error", "Local Original Safety", "Delete Boundaries"]
  },
  {
    id: "public-profile-social", title: "Public Profile / Social Hub｜Legacy-based Final Candidate", shortTitle: "Public Profile", direction: "Legacy", directionLocked: true,
    candidateTitle: "LAFAYETTE DIRECTION: LEGACY · FINAL CANDIDATE", candidateVersion: "Legacy Final Candidate",
    summary: "公开身份 → 关系 → Restaurant / Activity / List evidence 采用 Legacy 骨架；Current 权限和安全动作保留。",
    visuals: [
      r2v("CURRENT iOS", "Current Public Profile", R2_ATLAS + "core-parity-public-profile-after.png", "改造前公开身份与关系。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy Public Profile", R2_LEGACY + "legacy-fb127e9-public-profile-social-1280x720.png", "fb127e9 · 真实 follow/friend、足迹、动态与食单。")
    ],
    fuseVisuals: [r2v("FINAL iOS — REAL IMPLEMENTATION", "Public Profile Legacy-based Final Candidate", R2_FORMAL + "public-profile-legacy-final-candidate.png", "正式分支真实 SwiftUI：身份 → 关系 → 餐厅/动态/食单证据。")],
    legacyBase: ["公开身份 → 关系 → Restaurant/Activity/List 证据。"],
    currentAdditions: ["visibility、public cache、Report、Block、公开 Lists 与分享。", "Worker-backed follow、likes、comments、isolation 与 permissions。"],
    proposedFinal: ["Legacy 公开主页层级嵌入 Current 安全动作与内容能力。"],
    recommendation: "方向已确定为 Legacy；请核对 identity → relationship → evidence 的几何顺序。",
    regions: ["Header", "Social Metrics", "Primary Actions", "Content Tabs", "Restaurant Evidence", "Activity Feed", "Public Lists", "Report / Block"]
  },
  {
    id: "lists-density", title: "Lists / Public Lists｜Legacy-based Final Candidate", shortTitle: "Lists", direction: "Legacy", directionLocked: true,
    candidateTitle: "LAFAYETTE DIRECTION: LEGACY · FINAL CANDIDATE", candidateVersion: "Legacy Final Candidate",
    summary: "采用 Legacy collection/ranked 层级和紧凑卡片密度；Current 同步、权限、分享和 canonical image 保留。",
    visuals: [
      r2v("CURRENT iOS", "Current Public Ranking", R2_ATLAS + "p4-f-own-public-ranking.png", "改造前排名与公开状态。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy Public Ranked List", R2_LEGACY + "legacy-fb127e9-lists-public-list-1280x720.png", "fb127e9 · Profile → Lists。")
    ],
    fuseVisuals: [r2v("FINAL iOS — REAL IMPLEMENTATION", "Lists Legacy-based Final Candidate", R2_FORMAL + "lists-legacy-final-candidate.png", "正式分支真实 SwiftUI：collection/ranked、封面、可见性与紧凑顺序。")],
    legacyBase: ["collection / ranked 区分、封面、可见性与 Restaurant 顺序。", "排名与成员管理优先。"],
    currentAdditions: ["SwiftData/Worker、owner isolation、public cache、link sharing 与 visibility contract。", "canonical Restaurant image、stable ID；加入食单不隐式改变想去。"],
    proposedFinal: ["高密度榜单骨架中呈现真实图片、排序、权限与分享。"],
    recommendation: "方向已确定为 Legacy；请核对卡片密度与 Current 能力没有互相挤压。",
    regions: ["Header", "Cover", "Visibility", "Ranking", "Restaurant Rows", "Membership Actions", "Sharing", "Empty / Long State"]
  },
  {
    id: "analytics-compositions", title: "Analytics × 4｜Legacy-based Final Candidates", shortTitle: "Analytics × 4", direction: "Legacy", directionLocked: true,
    candidateTitle: "LAFAYETTE DIRECTION: LEGACY · FINAL CANDIDATES", candidateVersion: "Legacy Final Candidates",
    summary: "四页都采用历史已批准的中心 Food Hero、四周 callout、留白与代表餐厅图文构图；算法仍为 Current。",
    visuals: [
      r2v("APPROVED HISTORICAL REFERENCE", "Analysis 家族：我的口味档案", R2_ATLAS + "p4-a-taste-profile.png", "已确认的中心 Food Hero 分析家族。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 最佳饭搭子", R2_LEGACY + "legacy-fb127e9-companion-analysis-1280x720.png", "fb127e9。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 谁最会种草", R2_LEGACY + "legacy-fb127e9-recommendation-source-analysis-1280x720.png", "fb127e9。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 本月回顾", R2_LEGACY + "legacy-fb127e9-monthly-review-analysis-1280x720.png", "fb127e9。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 年度回顾", R2_LEGACY + "legacy-fb127e9-annual-review-analysis-1280x720.png", "fb127e9。")
    ],
    fuseVisuals: [
      r2v("FINAL iOS — REAL IMPLEMENTATION", "最佳饭搭子 Final Candidate", R2_FORMAL + "analytics-companion-legacy-final-candidate.png", "中心餐饮 Hero、四周真实关系节点。"),
      r2v("FINAL iOS — REAL IMPLEMENTATION", "谁最会种草 Final Candidate", R2_FORMAL + "analytics-source-legacy-final-candidate.png", "来源票据、中心 Food Hero 与四周结论。"),
      r2v("FINAL iOS — REAL IMPLEMENTATION", "本月回顾 Final Candidate", R2_FORMAL + "analytics-monthly-legacy-final-candidate.png", "中心 Food Hero + 四周月度节点。"),
      r2v("FINAL iOS — REAL IMPLEMENTATION", "年度回顾 Final Candidate", R2_FORMAL + "analytics-annual-legacy-final-candidate.png", "中心 Food Hero + 四周年度轨迹节点。")
    ],
    legacyBase: ["中心 Food Hero、surrounding callouts/nodes、留白与代表餐厅图文。"],
    currentAdditions: ["owner-scoped analyzer、sample sufficiency、nil/empty、正式名称。", "月/年轨迹、消费、privacy、Food/Dining semantic rules 与 Poster Preview。"],
    proposedFinal: ["四页共享 infographic 视觉语法，但按关系、来源、月度、年度形成不同故事。"],
    recommendation: "方向已确定为 Legacy；四张 Final Candidate 必须逐张查看。",
    regions: ["Header", "Food Hero", "Surrounding Nodes", "Main Insight", "TOP3", "Distribution", "Restaurant Imagery", "Footer"]
  },
  {
    id: "poster-family", title: "五类分享海报｜Redesign Candidate A / B", shortTitle: "海报 × 5", direction: "Needs redesign",
    candidateTitle: "REDESIGN CANDIDATES A / B — NOT YET APPROVED", candidateVersion: "A / B",
    summary: "正式 Poster contract 尚未修改；两套都是真实 9:16 SwiftUI renderer 候选，等待 Lafayette 选择。",
    visuals: [
      r2v("CURRENT iOS", "Current 口味海报", R2_ATLAS + "p4-a-9x16-poster.png", "当前正式 renderer。"),
      r2v("CURRENT iOS", "Current 饭搭子海报", R2_ATLAS + "p4-b-9x16-poster.png", "当前正式 renderer。"),
      r2v("CURRENT iOS", "Current 种草海报", R2_ATLAS + "p4-c-9x16-poster.png", "当前正式 renderer。"),
      r2v("CURRENT iOS", "Current 月度海报", R2_ATLAS + "p4-d-9x16-monthly-poster.png", "当前正式 renderer。"),
      r2v("CURRENT iOS", "Current 年度海报", R2_ATLAS + "p4-e-9x16-annual-poster.png", "当前正式 renderer。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 口味海报", R2_LEGACY + "legacy-fb127e9-taste-profile-poster-1280x720.png", "fb127e9。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 饭搭子海报", R2_LEGACY + "legacy-fb127e9-companion-poster-1280x720.png", "fb127e9。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 种草海报", R2_LEGACY + "legacy-fb127e9-recommendation-source-poster-1280x720.png", "fb127e9。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 月度海报", R2_LEGACY + "legacy-fb127e9-monthly-review-poster-1280x720.png", "fb127e9。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy 年度海报", R2_LEGACY + "legacy-fb127e9-annual-review-poster-1280x720.png", "fb127e9。")
    ],
    fuseVisuals: [
      r2v("CANDIDATE A — REAL 9:16 SWIFTUI", "我的口味档案 · A", R2_CANDIDATE + "poster-taste-a.png", "Radial infographic family。"),
      r2v("CANDIDATE B — REAL 9:16 SWIFTUI", "我的口味档案 · B", R2_CANDIDATE + "poster-taste-b.png", "Editorial receipt family。"),
      r2v("CANDIDATE A — REAL 9:16 SWIFTUI", "最佳饭搭子 · A", R2_CANDIDATE + "poster-companion-a.png", "Radial infographic family。"),
      r2v("CANDIDATE B — REAL 9:16 SWIFTUI", "最佳饭搭子 · B", R2_CANDIDATE + "poster-companion-b.png", "Editorial receipt family。"),
      r2v("CANDIDATE A — REAL 9:16 SWIFTUI", "谁最会种草 · A", R2_CANDIDATE + "poster-source-a.png", "Radial infographic family。"),
      r2v("CANDIDATE B — REAL 9:16 SWIFTUI", "谁最会种草 · B", R2_CANDIDATE + "poster-source-b.png", "Editorial receipt family。"),
      r2v("CANDIDATE A — REAL 9:16 SWIFTUI", "本月回顾 · A", R2_CANDIDATE + "poster-monthly-a.png", "Radial infographic family。"),
      r2v("CANDIDATE B — REAL 9:16 SWIFTUI", "本月回顾 · B", R2_CANDIDATE + "poster-monthly-b.png", "Editorial receipt family。"),
      r2v("CANDIDATE A — REAL 9:16 SWIFTUI", "年度回顾 · A", R2_CANDIDATE + "poster-annual-a.png", "Radial infographic family。"),
      r2v("CANDIDATE B — REAL 9:16 SWIFTUI", "年度回顾 · B", R2_CANDIDATE + "poster-annual-b.png", "Editorial receipt family。")
    ],
    legacyBase: ["专门设计的传播海报，不是页面截图。", "五类共享品牌识别，但故事重点不同。"],
    currentAdditions: ["SwiftUI 9:16、ImageRenderer、Share/Save、temp lifecycle、privacy、footer/QR。", "Food Hero、真实餐厅图片优先和语义边界。"],
    proposedFinal: ["A：中心 Food Hero + 四周数据节点。", "B：编辑式票据叙事 + 代表餐厅图；选择前不改正式 visual contract。"],
    recommendation: "按五个主题横向比较 A/B；不自动批准任何一套。",
    regions: ["Header", "Food Hero", "Key Conclusion", "Data Callouts", "Restaurant Imagery", "Brand Footer", "QR / Privacy", "9:16 Composition"]
  },
  {
    id: "premium-paywall", title: "Premium Paywall｜Legacy-based Final Candidate", shortTitle: "Premium", direction: "Legacy", directionLocked: true,
    candidateTitle: "LAFAYETTE DIRECTION: LEGACY · FINAL CANDIDATE", candidateVersion: "Legacy Final Candidate",
    summary: "采用 Legacy layout/hierarchy；approved hamburger 不重绘，StoreKit/server entitlement 事实保持 Current。",
    visuals: [
      r2v("CURRENT iOS", "Current Free Paywall", R2_ATLAS + "p4-h-free-paywall.png", "改造前 Paywall。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy Premium Paywall", R2_LEGACY + "legacy-fb127e9-premium-paywall-1280x720.png", "fb127e9。"),
      r2v("APPROVED HISTORICAL REFERENCE", "Approved Premium Hamburger", R2_ATLAS + "core-parity-approved-premium-hamburger.png", "明确批准的 Premium identity asset。")
    ],
    fuseVisuals: [r2v("FINAL iOS — REAL IMPLEMENTATION", "Premium Legacy-based Final Candidate", R2_FORMAL + "premium-legacy-final-candidate.png", "正式分支真实 SwiftUI：approved hamburger + 紧凑权益层级。")],
    legacyBase: ["Approved Hamburger 作为 Premium identity core。", "清楚的权益层级与 Free/Premium 差异。"],
    currentAdditions: ["StoreKit 2、server entitlement、restore、transaction updates、expiry/refund/revoke、Feature Registry。", "无真实 Product 时不显示假价格或假交易。"],
    proposedFinal: ["Hamburger Hero → 权益 → 真实产品事实 → 购买/恢复 → Legal。"],
    recommendation: "方向已确定为 Legacy；请核对汉堡外的结构与真实商业事实表达。",
    regions: ["Header", "Approved Hamburger", "Benefit Hierarchy", "Product Facts", "Purchase CTA", "Restore", "Legal", "Free / Premium States"]
  },
  {
    id: "settings-data", title: "Settings / Data｜Current Approved · Frozen", shortTitle: "Settings", direction: "Current", directionLocked: true,
    candidateTitle: "CURRENT APPROVED · FROZEN", candidateVersion: "Current Frozen",
    summary: "Lafayette 已选择 CURRENT；除 bug、Accessibility、Dynamic Type、localization overflow 或 security/release bug 外不得重做。",
    visuals: [
      r2v("CURRENT iOS", "Settings Root", R2_ATLAS + "final-atlas-settings-root.png", "Current 正式 IA。"),
      r2v("CURRENT iOS", "Backup Privacy", R2_ATLAS + "final-atlas-backup-export-privacy.png", "Current 数据安全提示。"),
      r2v("CURRENT iOS", "Import Preflight", R2_ATLAS + "final-atlas-import-preflight.png", "Current Import。"),
      r2v("CURRENT iOS", "Sync Pending", R2_ATLAS + "final-atlas-sync-pending.png", "Current Sync。"),
      r2v("LEGACY WEB — REAL SCREENSHOT", "Legacy Settings / Data", R2_LEGACY + "legacy-fb127e9-settings-data-1280x720.png", "历史对照，不再驱动重做。")
    ],
    fuseVisuals: [r2v("CURRENT iOS — FROZEN", "Settings Current Frozen", R2_FORMAL + "settings-current-frozen.png", "当前正式 Settings；本轮只记录冻结。")],
    legacyBase: ["历史分组仅保留为证据。"],
    currentAdditions: ["Account、Data & Backup、Sync、Privacy、Permissions、Storage、Premium、Help、About。", "Backup/Import 安全、权限真实状态、Legal、版本与 Release-safe 条件显示。"],
    proposedFinal: ["保持 Current 原生高可读密度与正式 Settings IA。"],
    recommendation: "CURRENT APPROVED / FROZEN；不需要重新选择视觉方向。",
    regions: ["Header", "Account", "Data & Backup", "Sync", "Privacy", "Permissions", "Storage", "Premium", "Help", "About"]
  }
];

function frozen(choice) { return { choice, frozen: true, notes: "Round 1 Lafayette approval" }; }

window.round2InitialState = {
  "profile-density": { decision: "FUSE", regions: { Header: frozen("KEEP LEGACY"), Settings: frozen("KEEP LEGACY") } },
  "visit-editor-density": { decision: "FUSE", regions: {} },
  "dish-photo-composition": { decision: "Legacy", regions: {} },
  "public-profile-social": { decision: "Legacy", regions: {} },
  "lists-density": { decision: "Legacy", regions: {} },
  "analytics-compositions": { decision: "Legacy", regions: {} },
  "poster-family": { decision: "Needs redesign", regions: {} },
  "premium-paywall": { decision: "Legacy", regions: {} },
  "settings-data": { decision: "Current", regions: {
    Header: frozen("KEEP CURRENT"), Account: frozen("KEEP CURRENT"), "Data & Backup": frozen("KEEP CURRENT"),
    Sync: frozen("KEEP CURRENT"), Privacy: frozen("KEEP CURRENT"), Permissions: frozen("KEEP CURRENT"),
    Storage: frozen("KEEP CURRENT"), Premium: frozen("KEEP CURRENT"), Help: frozen("KEEP CURRENT"), About: frozen("KEEP CURRENT")
  } }
};
