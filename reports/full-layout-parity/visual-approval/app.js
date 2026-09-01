const LEGACY = "../legacy-reference-screenshots/";
const FUSE = "fuse-candidates/";
const ATLAS = "../final-atlas/";

const decisions = window.round3Decisions || window.round2Decisions || [
  {
    id: "profile-density",
    title: "Profile 头部与 Dashboard",
    shortTitle: "Profile",
    summary: "以真实 Legacy Web Dashboard topology 为基础，保留 Current 的 Premium、Social、Sharing、Settings 与正式统计口径。",
    visuals: [
      v("CURRENT iOS", "当前 Premium Profile", ATLAS + "final-atlas-profile-premium-analytics.png", "当前登录态与 Analytics 入口。"),
      v("CURRENT iOS", "当前长文字 Profile", ATLAS + "final-atlas-visual-qa-long-text-profile.png", "Current 长用户名与高密度状态。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy Profile Dashboard", LEGACY + "legacy-fb127e9-profile-dashboard-1280x720.png", "fb127e9 · / → My/Profile · 1280×720。真实历史 Dashboard。"),
      v("APPROVED HISTORICAL REFERENCE", "历史 Profile Reference", "../../full-product-parity-assets/web-profile-before.jpg", "已保存的历史 Web reference。"),
    ],
    fuseVisuals: [v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Profile FUSE V1", FUSE + "fuse-v1-profile-real-implementation.png", "独立 preview branch 的 DEBUG SwiftUI 实现；固定 Simulator 实际截图。")],
    legacyBase: ["紧凑身份头部与高密度 Dashboard 骨架。", "横向关系/统计、并排核心入口、统一回味、食单与洞察分组。"],
    currentAdditions: ["avatar / name / joined date / edit、Premium、关注 / 被关注。", "去过 / 想去 / 总消费、今天吃什么、我的口味档案、三类回味、食单、最佳饭搭子、谁最会种草。", "Current Social、Sharing、Settings 与安全边界。"],
    proposedFinal: ["紧凑身份 → 社交关系 → 核心统计 → 核心入口 → 回味 → 食单 → 洞察 → 次级 Settings。", "使用当前共享 tokens/components，不恢复废弃字段，不删除 Current-only 能力。"],
    recommendation: "Recommended: FUSE。先按区域审批 V1；KEEP 的区域立即冻结。",
    regions: ["Header", "Social Metrics", "Main Statistics", "Core Entries", "Memory / 回味", "Lists", "Insights", "Settings"],
  },
  {
    id: "visit-editor-density",
    title: "Visit Editor 最终信息密度",
    shortTitle: "Visit Editor",
    summary: "融合 Legacy 单次用餐叙事顺序与 Current 完整 Visit 合同、nil 语义、离线保存和媒体生命周期。",
    visuals: [
      v("CURRENT iOS", "Visit 核心表单", ATLAS + "final-atlas-visit-core-form.png", "Current 核心表单。"),
      v("CURRENT iOS", "Visit Rich State", ATLAS + "final-atlas-visit-rich-photo-dish-context.png", "Current 菜品、照片与上下文。"),
      v("CURRENT iOS", "多维评分", ATLAS + "final-atlas-visit-detailed-ratings.png", "Current 多维评分。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy Visit Editor", LEGACY + "legacy-fb127e9-visit-editor-1280x720.png", "fb127e9 · Restaurant → repeat visit · 1280×720。")
    ],
    fuseVisuals: [v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Visit Editor FUSE V1", FUSE + "fuse-v1-visit-editor-real-implementation.png", "Legacy single-flow density + Current Visit contract。")],
    legacyBase: ["一次到访的自然叙事顺序与紧凑日记式分组。", "餐厅上下文、评分、内容和备注保持视觉连续。"],
    currentAdditions: ["nil/optional、多维评分、消费、饭搭子、推荐来源与正式用餐上下文。", "SwiftData local-first、离线队列、Dish/Photo 生命周期；六个废弃字段继续 RETIRE。"],
    proposedFinal: ["按 Legacy 叙事组织 Current 完整字段，压缩重复留白而不隐藏状态。", "复杂媒体/上下文渐进展开，唯一真实保存逻辑保持不变。"],
    recommendation: "Recommended: FUSE。按字段组逐区冻结，不把整个长表单一次性定案。",
    regions: ["Header", "Restaurant Context", "Core Experience", "Ratings", "Dish / Photo Entry", "Dining Context", "Notes", "Save CTA"],
  },
  {
    id: "dish-photo-composition",
    title: "Dish / Photo Manager 最终构图",
    shortTitle: "Dish / Photo",
    summary: "Legacy 的用餐故事构图与 Current 的 local original、上传、重试、复用及独立删除必须同时成立。",
    visuals: [
      v("CURRENT iOS", "Current Dish / Photo", ATLAS + "final-atlas-visit-rich-photo-dish-context.png", "Current manager-style 状态。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy Dish / Photo Manager", LEGACY + "legacy-fb127e9-visit-dish-photo-manager-1280x720.png", "fb127e9 · Visit Editor lower section · 1280×720。真实历史空 manager 状态，不伪造内容。")
    ],
    fuseVisuals: [v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Dish / Photo FUSE V1", FUSE + "fuse-v1-dish-photo-real-implementation.png", "真实图片故事构图 + Current 生命周期状态。")],
    legacyBase: ["菜品与实拍属于一次用餐故事，和 Restaurant / Visit 连续呈现。", "图文关系优先于抽象工具面板。"],
    currentAdditions: ["独立 Dish / VisitDish / PhotoAsset、local original、上传下载、重试、复用与独立删除。", "Restaurant 真实图片优先与不可丢失照片边界。"],
    proposedFinal: ["editorial 图文构图中明确暴露同步、失败、重试和删除状态。", "继续复用当前 manager/service，不建立第二套媒体业务逻辑。"],
    recommendation: "Recommended: FUSE，但生命周期和安全区域只有明确 KEEP 后才能冻结。",
    regions: ["Header", "Photo Story", "Upload Status", "Dish List", "Add / Edit Actions", "Retry / Error", "Local Original Safety", "Delete Boundaries"],
  },
  {
    id: "public-profile-social",
    title: "Public Profile / Social Hub 几何结构",
    shortTitle: "Public Profile",
    summary: "Legacy 公开身份与内容证据骨架，融合 Current 的 visibility、Report、Block、公开 Lists、分享和服务端 Social。",
    visuals: [
      v("CURRENT iOS", "Current Public Profile", ATLAS + "core-parity-public-profile-after.png", "Current 公开身份与关系。"),
      v("CURRENT iOS", "Current Community", ATLAS + "p3-d-community-feed.png", "Current 社交内容证据。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy Public Profile", LEGACY + "legacy-fb127e9-public-profile-social-1280x720.png", "fb127e9 · local D1 TestUser04 · 1280×720。真实 follow/friend、足迹、动态与食单。")
    ],
    fuseVisuals: [v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Public Profile FUSE V1", FUSE + "fuse-v1-public-profile-real-implementation.png", "Legacy identity → relationship → evidence + Current safety actions。")],
    legacyBase: ["公开身份 → 关系 → Restaurant/Activity/List 证据。", "先解释这个人是谁，再展示公开内容。"],
    currentAdditions: ["visibility、public cache、Report、Block、公开 Lists 与分享。", "Worker-backed 关注、点赞、评论、隔离与权限。"],
    proposedFinal: ["使用 Legacy 公开主页层级嵌入 Current 安全动作与内容能力。", "不复制私人 Profile Dashboard，不使用本地假社交状态。"],
    recommendation: "Recommended: FUSE；安全动作与权限逻辑默认只可 KEEP CURRENT。",
    regions: ["Header", "Social Metrics", "Primary Actions", "Content Tabs", "Restaurant Evidence", "Activity Feed", "Public Lists", "Report / Block"],
  },
  {
    id: "lists-density",
    title: "Lists / Public Lists 最终卡片密度",
    shortTitle: "Lists",
    summary: "以 Legacy collection/ranked 层级和高密度顺序为基础，保留 Current 同步、权限、分享与 canonical Restaurant image。",
    visuals: [
      v("CURRENT iOS", "Current Public Ranking", ATLAS + "p4-f-own-public-ranking.png", "Current 排名与公开状态。"),
      v("CURRENT iOS", "Current Public List Actions", ATLAS + "p4-f-public-list-to-want-to-go.png", "Current Restaurant 操作。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy Public Ranked List", LEGACY + "legacy-fb127e9-lists-public-list-1280x720.png", "fb127e9 · Profile → Lists · 1280×720。隔离本地预览中通过 Legacy UI 创建。")
    ],
    fuseVisuals: [v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Lists FUSE V1", FUSE + "fuse-v1-lists-real-implementation.png", "高密度排名骨架 + Current 图片、可见性与分享。")],
    legacyBase: ["collection / ranked 区分、封面、可见性与 Restaurant 顺序。", "排名和成员管理是主任务。"],
    currentAdditions: ["SwiftData/Worker、owner isolation、公开缓存、link sharing 与 visibility contract。", "canonical Restaurant image、稳定 ID；加入食单不隐式改变想去。"],
    proposedFinal: ["高密度榜单骨架中呈现真实餐厅图、排序、权限和分享。", "媒体比例不吞掉排名与管理效率。"],
    recommendation: "Recommended: FUSE。列表行密度、封面与操作区可分别审批。",
    regions: ["Header", "Cover", "Visibility", "Ranking", "Restaurant Rows", "Membership Actions", "Sharing", "Empty / Long State"],
  },
  {
    id: "analytics-compositions",
    title: "四类 Analytics 页面最终构图",
    shortTitle: "Analytics × 4",
    summary: "最佳饭搭子、谁最会种草、本月回顾和年度回顾都必须是独立信息图，而不是普通 VStack Card Dashboard。",
    visuals: [
      v("CURRENT iOS", "最佳饭搭子", ATLAS + "p4-b-companion-detail.png", "Current Companion。"),
      v("CURRENT iOS", "谁最会种草", ATLAS + "p4-c-recommendation-source-overview.png", "Current Source。"),
      v("CURRENT iOS", "本月回顾", ATLAS + "p4-d-monthly-recap-current.png", "Current Monthly。"),
      v("CURRENT iOS", "年度回顾", ATLAS + "p4-e-annual-recap-current.png", "Current Annual。"),
      v("APPROVED HISTORICAL REFERENCE", "Analysis 家族：我的口味档案", ATLAS + "p4-a-taste-profile.png", "已确认的中心 Food Hero 分析家族。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 最佳饭搭子", LEGACY + "legacy-fb127e9-companion-analysis-1280x720.png", "fb127e9 · Profile Analytics · 1280×720。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 谁最会种草", LEGACY + "legacy-fb127e9-recommendation-source-analysis-1280x720.png", "fb127e9 · Profile Analytics · 1280×720。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 本月回顾", LEGACY + "legacy-fb127e9-monthly-review-analysis-1280x720.png", "fb127e9 · 真实历史空状态（固定数据止于 2026-08）。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 年度回顾", LEGACY + "legacy-fb127e9-annual-review-analysis-1280x720.png", "fb127e9 · Profile Analytics · 1280×720。")
    ],
    fuseVisuals: [
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "最佳饭搭子 FUSE V1", FUSE + "fuse-v1-analytics-companion-real-implementation.png", "中心 Food Hero、四周数据节点、结论、TOP3、分布。"),
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "谁最会种草 FUSE V1", FUSE + "fuse-v1-analytics-source-real-implementation.png", "同一家族，不机械复制数据语义。"),
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "本月回顾 FUSE V1", FUSE + "fuse-v1-analytics-monthly-real-implementation.png", "真实 Rich Demo 月度语义候选。"),
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "年度回顾 FUSE V1", FUSE + "fuse-v1-analytics-annual-real-implementation.png", "真实 Rich Demo 年度语义候选。")
    ],
    legacyBase: ["真实 Restaurant/Visit/饭搭子/来源数据语义。", "已批准家族的中心 Food Hero、四周 callout、留白与代表餐厅图文。"],
    currentAdditions: ["owner-scoped analyzer、样本充足度、nil/empty、正式新名称。", "月/年轨迹、消费、隐私、Food/Dining 语义区分和 Poster Preview。"],
    proposedFinal: ["四页共享视觉语法但按关系、来源、月度和年度形成不同故事。", "真实餐厅图片优先；装饰不冒充数据结论。"],
    recommendation: "Recommended: FUSE。Analytics 按共同区域冻结，若某一页需例外应写入区域 Notes。",
    regions: ["Header", "Food Hero", "Surrounding Nodes", "Main Insight", "TOP3", "Distribution", "Restaurant Imagery", "Footer"],
  },
  {
    id: "poster-family",
    title: "五类分享海报 V1 视觉家族",
    shortTitle: "海报 × 5",
    summary: "五张必须是独立 9:16 原生 renderer；审批的是实际传播构图，不是 Share Sheet 是否能打开。",
    visuals: [
      v("CURRENT iOS", "Current 口味海报", ATLAS + "p4-a-9x16-poster.png", "Current Taste。"),
      v("CURRENT iOS", "Current 饭搭子海报", ATLAS + "p4-b-9x16-poster.png", "Current Companion。"),
      v("CURRENT iOS", "Current 种草海报", ATLAS + "p4-c-9x16-poster.png", "Current Source。"),
      v("CURRENT iOS", "Current 月度海报", ATLAS + "p4-d-9x16-monthly-poster.png", "Current Monthly。"),
      v("CURRENT iOS", "Current 年度海报", ATLAS + "p4-e-9x16-annual-poster.png", "Current Annual。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 口味海报", LEGACY + "legacy-fb127e9-taste-profile-poster-1280x720.png", "fb127e9 · legacy renderer。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 饭搭子海报", LEGACY + "legacy-fb127e9-companion-poster-1280x720.png", "fb127e9 · legacy renderer。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 种草海报", LEGACY + "legacy-fb127e9-recommendation-source-poster-1280x720.png", "fb127e9 · legacy renderer。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 月度海报", LEGACY + "legacy-fb127e9-monthly-review-poster-1280x720.png", "fb127e9 · 真实历史空状态海报。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy 年度海报", LEGACY + "legacy-fb127e9-annual-review-poster-1280x720.png", "fb127e9 · legacy renderer。")
    ],
    fuseVisuals: [
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "口味海报 FUSE V1", FUSE + "fuse-v1-poster-taste-real-implementation.png", "原生 9:16 SwiftUI 实际截图。"),
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "饭搭子海报 FUSE V1", FUSE + "fuse-v1-poster-companion-real-implementation.png", "原生 9:16 SwiftUI 实际截图。"),
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "种草海报 FUSE V1", FUSE + "fuse-v1-poster-source-real-implementation.png", "原生 9:16 SwiftUI 实际截图。"),
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "月度海报 FUSE V1", FUSE + "fuse-v1-poster-monthly-real-implementation.png", "原生 9:16 SwiftUI 实际截图。"),
      v("FUSE CANDIDATE — REAL IMPLEMENTATION", "年度海报 FUSE V1", FUSE + "fuse-v1-poster-annual-real-implementation.png", "原生 9:16 SwiftUI 实际截图。")
    ],
    legacyBase: ["分享内容是专门设计的传播海报，不是页面截图。", "主题共享品牌识别，同时保留不同故事重点。"],
    currentAdditions: ["五类 SwiftUI 9:16、ImageRenderer、Share/Save、临时文件、隐私替换、品牌 footer/QR。", "Food Hero、真实餐厅图片优先和语义边界。"],
    proposedFinal: ["保留 Current 原生安全生命周期，融合 Legacy 的传播层级和更强餐饮故事。", "五张作为家族审批，不伪造 QR、价格或数据。"],
    recommendation: "Recommended: FUSE 候选进入区域审批；五张不是自动批准。",
    regions: ["Header", "Food Hero", "Key Conclusion", "Data Callouts", "Restaurant Imagery", "Brand Footer", "QR / Privacy", "9:16 Composition"],
  },
  {
    id: "premium-paywall",
    title: "Premium Paywall 最终结构",
    shortTitle: "Premium",
    summary: "已批准 Hamburger 保持不变；融合 Legacy 转化层级和 Current StoreKit/server entitlement 事实。",
    visuals: [
      v("CURRENT iOS", "Current Free Paywall", ATLAS + "p4-h-free-paywall.png", "Current fail-closed Paywall。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy Premium Paywall", LEGACY + "legacy-fb127e9-premium-paywall-1280x720.png", "fb127e9 · ?testAccount=free · 1280×720。"),
      v("APPROVED HISTORICAL REFERENCE", "Approved Premium Hamburger", ATLAS + "core-parity-approved-premium-hamburger.png", "明确批准的是汉堡身份资产。")
    ],
    fuseVisuals: [v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Premium FUSE V1", FUSE + "fuse-v1-paywall-real-implementation.png", "批准汉堡 + Current capability/entitlement truth。")],
    legacyBase: ["批准 Hamburger 作为 Premium 身份核心。", "清楚的权益层级和 Free/Premium 差异。"],
    currentAdditions: ["StoreKit 2、server entitlement、restore、transaction updates、expiry/refund/revoke、Feature Registry。", "无真实 Product 时不显示假价格或假交易。"],
    proposedFinal: ["Hamburger Hero → 权益 → 真实产品事实 → 购买/恢复 → Legal。", "商业信息由真实 Product 驱动，外部配置前 fail-closed。"],
    recommendation: "Recommended: FUSE；已批准汉堡区域应 KEEP FUSE/Legacy 后冻结。",
    regions: ["Header", "Approved Hamburger", "Benefit Hierarchy", "Product Facts", "Purchase CTA", "Restore", "Legal", "Free / Premium States"],
  },
  {
    id: "settings-data",
    title: "Settings / Data 工具页最终视觉密度",
    shortTitle: "Settings",
    summary: "使用 Legacy 分组证据，但必须保留 Current Settings Foundation、Backup/Import/Sync 安全边界与原生可扫描性。",
    visuals: [
      v("CURRENT iOS", "Settings Root", ATLAS + "final-atlas-settings-root.png", "Current IA。"),
      v("CURRENT iOS", "Backup Privacy", ATLAS + "final-atlas-backup-export-privacy.png", "Current 数据安全提示。"),
      v("CURRENT iOS", "Import Preflight", ATLAS + "final-atlas-import-preflight.png", "Current Import。"),
      v("CURRENT iOS", "Sync Pending", ATLAS + "final-atlas-sync-pending.png", "Current Sync。"),
      v("CURRENT iOS", "Permissions", ATLAS + "final-atlas-permissions.png", "Current 权限。"),
      v("CURRENT iOS", "About", ATLAS + "final-atlas-about.png", "Current About。"),
      v("LEGACY WEB — REAL SCREENSHOT", "Legacy Settings / Data", LEGACY + "legacy-fb127e9-settings-data-1280x720.png", "fb127e9 · ?testAccount=free · 1280×720。")
    ],
    fuseVisuals: [v("FUSE CANDIDATE — REAL IMPLEMENTATION", "Settings FUSE V1", FUSE + "fuse-v1-settings-real-implementation.png", "Legacy grouped tools + Current formal Settings IA。")],
    legacyBase: ["账户与数据工具按任务分组，不把能力散落在 Profile。", "保持快速扫读与低学习成本。"],
    currentAdditions: ["Account、Data & Backup、Sync、Privacy、Permissions、Storage、Premium、Help、About。", "Backup/Import 安全、权限真实状态、Legal、版本与 Release-safe 条件显示。"],
    proposedFinal: ["原生高可读密度为基础，以 Current tokens 统一轻边框与层级。", "Food/Dining 仅低权重装饰，不冒充设置数据。"],
    recommendation: "Recommended: FUSE，但 Data/Sync/Permissions 的功能层级默认优先 KEEP CURRENT。",
    regions: ["Header", "Account", "Data & Backup", "Sync", "Privacy", "Permissions", "Storage", "Premium", "Help", "About"],
  },
];

function v(kind, title, src, caption) { return { kind, title, src, caption }; }

const storageKey = window.visualApprovalStorageKey || "tastemap.visualApproval.round2";
const referenceLibrary = window.LafayetteReferenceLibrary;
let reviewState = readState();
let lightboxItems = [];
let lightboxIndex = 0;
let zoom = 1;
let referenceRecords = [];
const referenceObjectURLs = new Map();

const referencePurposeLabels = {
  wholePage: "整页参考",
  region: "某个区域参考",
  composition: "构图参考",
  style: "风格参考",
  component: "组件参考",
};

const referenceStrengthLabels = {
  inspiration: "灵感参考",
  direction: "视觉方向",
  highFidelity: "高度复刻",
  geometry: "几何 / 构图 Source of Truth",
};

function escapeHTML(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");
}

const userTextReplacements = [
  ["Social Metrics", "关注数据"],
  ["Restaurant Evidence", "餐厅记录"],
  ["Activity Feed", "动态"],
  ["Public Lists", "公开食单"],
  ["Free / Premium States", "免费版 / Premium 状态"],
  ["Settings / Data", "设置 / 数据"],
  ["Restaurant Context", "餐厅信息"],
  ["Dining Context", "用餐情境"],
  ["Food Hero", "核心食物主视觉"],
  ["ImageRenderer", "原生图片渲染器"],
  ["StoreKit/server entitlement", "StoreKit / 服务端会员权益"],
  ["server entitlement", "服务端会员权益"],
  ["transaction updates", "交易状态更新"],
  ["expiry/refund/revoke", "到期 / 退款 / 撤销"],
  ["Feature Registry", "功能登记表"],
  ["owner-scoped analyzer", "按用户隔离的分析器"],
  ["sample sufficiency", "样本充足度"],
  ["Food/Dining semantic rules", "餐饮视觉语义规则"],
  ["Food/Dining", "餐饮视觉"],
  ["Poster Preview", "海报预览"],
  ["Restaurant/Activity/List evidence", "餐厅 / 动态 / 食单证据"],
  ["identity → relationship → evidence", "身份 → 关系 → 内容证据"],
  ["Restaurant / Activity / List evidence", "餐厅 / 动态 / 食单证据"],
  ["Worker-backed follow", "Worker 服务端关注关系"],
  ["public cache", "公开缓存"],
  ["owner isolation", "用户归属隔离"],
  ["link sharing", "链接分享"],
  ["visibility contract", "可见范围合同"],
  ["canonical Restaurant image", "统一餐厅图片"],
  ["canonical image", "统一图片呈现"],
  ["stable ID", "稳定 ID"],
  ["collection/ranked", "收藏型 / 排名型"],
  ["Share/Save", "分享 / 保存"],
  ["temp lifecycle", "临时文件生命周期"],
  ["footer/QR", "底部品牌区 / 二维码"],
  ["Radial infographic family", "环形信息图家族"],
  ["Editorial receipt family", "编辑式票据家族"],
  ["layout/hierarchy", "布局 / 层级"],
  ["Current formal Settings IA", "现版正式设置信息架构"],
  ["Current Settings Foundation", "现版设置基础架构"],
  ["Current Settings", "现版设置"],
  ["Settings IA", "设置信息架构"],
  ["Backup/Import", "备份 / 导入"],
  ["Data & Backup", "数据与备份"],
  ["Free/Premium", "免费版 / Premium"],
  ["Free / Premium", "免费版 / Premium"],
  ["Approved Premium Hamburger", "已确认的 Premium 汉堡"],
  ["approved hamburger", "已确认汉堡"],
  ["Approved Hamburger", "已确认汉堡"],
  ["Hamburger Hero", "汉堡主视觉"],
  ["Hamburger", "汉堡"],
  ["identity asset", "身份资产"],
  ["identity core", "身份核心"],
  ["Product facts", "商品信息"],
  ["Product Facts", "商品信息"],
  ["Restaurant → repeat visit", "餐厅 → 再次记录到访"],
  ["Visit Rich State", "到访丰富状态"],
  ["Visit 核心表单", "到访核心表单"],
  ["Visit contract", "到访数据合同"],
  ["VisitDish", "到访菜品关系"],
  ["Dish/Photo", "菜品 / 照片"],
  ["PhotoAsset", "照片资产"],
  ["local original", "本地原图"],
  ["local-first", "本地优先"],
  ["nil/optional", "空值 / 可选"],
  ["nil/empty", "空值 / 空状态"],
  ["optional", "可选"],
  ["RETIRE", "保持废弃"],
  ["manager-style", "管理面板式"],
  ["lower section", "下半部分"],
  ["single-flow density", "单流程信息密度"],
  ["follow/friend", "关注 / 好友"],
  ["follow", "关注"],
  ["likes", "点赞"],
  ["comments", "评论"],
  ["isolation", "隔离"],
  ["permissions", "权限"],
  ["visibility", "可见范围"],
  ["Report", "举报"],
  ["Block", "拉黑"],
  ["Sharing", "分享"],
  ["Social", "社交"],
  ["Activity", "动态"],
  ["Restaurant", "餐厅"],
  ["Privacy", "隐私"],
  ["privacy", "隐私"],
  ["surrounding callouts/nodes", "周边标注 / 节点"],
  ["surrounding callouts", "周边标注"],
  ["callouts/nodes", "标注 / 节点"],
  ["callout", "标注"],
  ["infographic", "信息图"],
  ["Accessibility", "辅助功能"],
  ["Dynamic Type", "动态字体"],
  ["localization overflow", "本地化内容溢出"],
  ["security/release bug", "安全 / 发布问题"],
  ["fail-closed", "默认关闭保护"],
  ["Rich Demo", "丰富演示数据"],
  ["compact", "紧凑"],
  ["topology", "结构"],
  ["renderer", "渲染器"],
  ["reference", "参考"],
  ["LAFAYETTE DIRECTION: LEGACY · FINAL CANDIDATES", "Lafayette 已确认方向：旧版 · 最终候选版"],
  ["LAFAYETTE DIRECTION: LEGACY · FINAL CANDIDATE", "Lafayette 已确认方向：旧版 · 最终候选版"],
  ["REDESIGN CANDIDATES A / B — NOT YET APPROVED", "重新设计候选版 A / B — 尚未确认"],
  ["FUSE CANDIDATE — REAL IMPLEMENTATION", "融合候选版 — 真实实现"],
  ["FUSE CANDIDATE V2 — NOT YET APPROVED", "融合候选版 V2 — 尚未确认"],
  ["FUSE CANDIDATE — NOT YET APPROVED", "融合候选版 — 尚未确认"],
  ["FINAL iOS — REAL IMPLEMENTATION", "最终 iOS — 真实实现"],
  ["LEGACY WEB — REAL SCREENSHOT", "旧版 Web — 真实截图"],
  ["APPROVED HISTORICAL REFERENCE", "已确认的历史参考"],
  ["CURRENT iOS — FROZEN", "现版 iOS — 已冻结"],
  ["CURRENT iOS", "现版 iOS"],
  ["CANDIDATE A — REAL 9:16 SWIFTUI", "候选版 A — 真实 9:16 SwiftUI"],
  ["CANDIDATE B — REAL 9:16 SWIFTUI", "候选版 B — 真实 9:16 SwiftUI"],
  ["Legacy-based Final Candidates", "以旧版为基础的最终候选版"],
  ["Legacy-based Final Candidate", "以旧版为基础的最终候选版"],
  ["Legacy Final Candidates", "旧版方向最终候选版"],
  ["Legacy Final Candidate", "旧版方向最终候选版"],
  ["Current Approved · Frozen", "现版已确认 · 已冻结"],
  ["CURRENT APPROVED · FROZEN", "现版已确认 · 已冻结"],
  ["CURRENT APPROVED / FROZEN", "现版已确认 / 已冻结"],
  ["KEEP CURRENT", "保留现版"],
  ["KEEP LEGACY", "保留旧版"],
  ["KEEP FUSE", "保留融合版"],
  ["Frozen YES", "已冻结"],
  ["Current-only", "现版独有"],
  ["FUSE V2", "融合候选版 V2"],
  ["FUSE V1", "融合候选版 V1"],
  ["Round 1 Lafayette approval", "第一轮 Lafayette 已确认"],
  ["NOT YET APPROVED", "尚未确认"],
  ["APPROVED FINAL", "最终确认"],
  ["APPROVED", "已确认"],
  ["CANDIDATES", "候选版"],
  ["CANDIDATE", "候选版"],
  ["Current Frozen", "现版已冻结"],
  ["Profile FUSE V2", "我的页面融合候选版 V2"],
  ["Profile FUSE V1", "我的页面融合候选版 V1"],
  ["Visit Editor FUSE V1", "到访记录融合候选版 V1"],
  ["FUSE Candidate V2", "融合候选版 V2"],
  ["FUSE Candidate", "融合候选版"],
  ["Candidate Version", "候选版本"],
  ["Candidate", "候选版"],
  ["Current Additions", "现版新增能力"],
  ["Legacy Base", "旧版基础"],
  ["Proposed Final Composition", "建议的最终构图"],
  ["Memory / 回味", "回味"],
  ["Public Profile / Social Hub", "公开主页 / 社交中心"],
  ["Public Profile", "公开主页"],
  ["Public Ranking", "公开榜单"],
  ["Public List Actions", "公开食单操作"],
  ["public Lists", "公开食单"],
  ["Premium Paywall", "Premium 会员页"],
  ["Paywall", "会员页"],
  ["Community", "社区"],
  ["Analysis", "分析"],
  ["Visit Editor", "到访记录"],
  ["Dish / Photo Manager", "菜品与照片管理"],
  ["Dish / Photo", "菜品与照片"],
  ["Analytics", "数据分析"],
  ["Profile", "我的页面"],
  ["Settings", "设置"],
  ["Dashboard", "信息总览"],
  ["Photo Story", "照片故事"],
  ["Upload Status", "上传状态"],
  ["Dish List", "菜品列表"],
  ["Add / Edit Actions", "添加 / 编辑操作"],
  ["Retry / Error", "重试 / 错误"],
  ["Local Original Safety", "本地原图安全"],
  ["Delete Boundaries", "删除边界"],
  ["Cover", "封面"],
  ["Visibility", "可见范围"],
  ["Ranking", "排名"],
  ["Restaurant Rows", "餐厅条目"],
  ["Membership Actions", "成员管理"],
  ["Sharing", "分享"],
  ["Empty / Long State", "空状态 / 长文本状态"],
  ["Key Conclusion", "核心结论"],
  ["Data Callouts", "数据标注"],
  ["Brand Footer", "底部品牌区"],
  ["QR / Privacy", "二维码 / 隐私"],
  ["9:16 Composition", "9:16 构图"],
  ["Approved Hamburger", "已确认汉堡"],
  ["Data & Backup", "数据与备份"],
  ["Account", "账户"],
  ["Sync", "同步"],
  ["Privacy", "隐私"],
  ["Permissions", "权限"],
  ["Storage", "存储"],
  ["Help", "帮助"],
  ["About", "关于"],
  ["Current", "现版"],
  ["Legacy", "旧版"],
  ["FUSE", "融合版"],
  ["CURRENT", "现版"],
  ["LEGACY", "旧版"],
  ["Pending", "待决定"],
  ["Final", "最终"],
  ["FINAL", "最终"],
  ["Free", "免费版"],
  ["Reference", "参考"],
  ["Recommended", "建议"],
  ["PENDING", "待决定"],
  ["direction", "方向"],
  ["preview branch", "预览分支"],
  ["DEBUG", "调试版"],
  ["Backup", "备份"],
  ["bug", "问题"],
  ["collection", "收藏型"],
  ["contract", "合同"],
  ["Dish", "菜品"],
  ["Entry", "入口"],
  ["Hero", "主视觉"],
  ["Hub", "中心"],
  ["IA", "信息架构"],
  ["Imagery", "图片"],
  ["Import", "导入"],
  ["Lists", "我的食单"],
  ["List", "食单"],
  ["Poster", "海报"],
  ["Preflight", "预检"],
  ["Product", "商品"],
  ["Public", "公开"],
  ["ranked", "排名型"],
  ["Ranked", "排名型"],
  ["Redesign", "重新设计"],
  ["Release-safe", "发布安全"],
  ["restore", "恢复购买"],
  ["Root", "首页"],
  ["Rows", "条目"],
  ["Taste", "口味"],
  ["Visit", "到访"],
  ["visual", "视觉"],
  ["Header", "顶部身份区"],
  ["Social Metrics", "关注数据"],
  ["Main Statistics", "主统计"],
  ["Core Entries", "核心入口"],
  ["Memory", "回味"],
  ["Insights", "洞察"],
  ["Restaurant Context", "餐厅信息"],
  ["Core Experience", "用餐体验"],
  ["Ratings", "评分"],
  ["Dish / Photo Entry", "菜品与照片"],
  ["Dining Context", "用餐情境"],
  ["Notes", "备注"],
  ["Save CTA", "保存按钮"],
  ["Primary Actions", "主要操作"],
  ["Content Tabs", "内容分类"],
  ["Restaurant Evidence", "餐厅记录"],
  ["Activity Feed", "动态"],
  ["Public Lists", "公开食单"],
  ["Report / Block", "举报 / 拉黑"],
  ["Food Hero", "核心食物主视觉"],
  ["Surrounding Nodes", "周边分析节点"],
  ["Main Insight", "核心洞察"],
  ["TOP3", "TOP 3"],
  ["Distribution", "分布"],
  ["Restaurant Imagery", "代表餐厅图片"],
  ["Footer", "底部品牌区"],
  ["Benefit Hierarchy", "会员权益"],
  ["Product Facts", "商品信息"],
  ["Purchase CTA", "购买按钮"],
  ["Restore", "恢复购买"],
  ["Legal", "法律信息"],
  ["Free / Premium States", "免费版 / Premium 状态"],
];

function displayText(value) {
  return userTextReplacements.reduce((result, [source, replacement]) => result.replaceAll(source, replacement), String(value ?? ""));
}

function displayDirection(value, includeMachineValue = false) {
  const labels = { Current: "现版", Legacy: "旧版", FUSE: "融合版", "Option A": "方案 A", "Option B": "方案 B", "Needs redesign": "重新设计" };
  const label = labels[value] || (value ? displayText(value) : "待决定");
  return includeMachineValue && value ? `${label}（${value}）` : label;
}

function displayChoice(value, includeMachineValue = false) {
  const labels = { "KEEP CURRENT": "保留现版", "KEEP LEGACY": "保留旧版", "KEEP FUSE": "保留融合版", CHANGE: "需要修改", "NEEDS REDESIGN": "重新设计" };
  const label = labels[value] || "待决定";
  return includeMachineValue && value ? `${label}（${value}）` : label;
}

function choiceExplanation(value) {
  return {
    "KEEP CURRENT": "采用当前 iOS 这一区域，并冻结。",
    "KEEP LEGACY": "采用旧版 Web 这一区域，并冻结。",
    "KEEP FUSE": "采用当前融合候选版这一区域，并冻结。",
    CHANGE: "当前方向基本保留，但这个区域还需要继续修改。",
    "NEEDS REDESIGN": "当前区域方向不对，下一版重新设计。",
  }[value] || "";
}

function displayNote(value) {
  return value === "Round 1 Lafayette approval" ? "第一轮 Lafayette 已确认" : String(value || "");
}

function readState() {
  try {
    const current = JSON.parse(localStorage.getItem(storageKey) || "null");
    if (current) return current;
    return structuredClone(window.visualApprovalInitialState || window.round2InitialState || {});
  } catch { return {}; }
}

function persistState() {
  try { localStorage.setItem(storageKey, JSON.stringify(reviewState)); } catch { /* session-only fallback */ }
}

function visualMarkup(visual, decisionTitle) {
  const normalized = visual.kind.toLowerCase();
  const kindClass = normalized.includes("legacy") || normalized.includes("旧版")
    ? " visual-card__kind--legacy"
    : normalized.includes("fuse") || normalized.includes("融合")
      ? " visual-card__kind--fuse"
      : normalized.includes("reference") || normalized.includes("参考")
        ? " visual-card__kind--reference"
        : "";
  const title = displayText(visual.title);
  const kind = displayText(visual.kind);
  const caption = displayText(visual.caption);
  return `<article class="visual-card">
    <div class="visual-card__meta"><div class="visual-card__title">${escapeHTML(title)}</div><span class="visual-card__kind${kindClass}">${escapeHTML(kind)}</span></div>
    <button class="visual-card__button" type="button" data-image-src="${escapeHTML(visual.src)}" data-image-title="${escapeHTML(title)}" data-image-kind="${escapeHTML(kind)}" data-image-caption="${escapeHTML(caption)}" aria-label="放大查看：${escapeHTML(displayText(decisionTitle))}，${escapeHTML(title)}">
      <img src="${escapeHTML(visual.src)}" alt="${escapeHTML(title)}" loading="lazy">
    </button><p class="visual-card__caption">${escapeHTML(caption)}</p></article>`;
}

function listMarkup(items) { return `<ul>${items.map((item) => `<li>${escapeHTML(displayText(item))}</li>`).join("")}</ul>`; }

function pageState(id) {
  reviewState[id] ||= {};
  reviewState[id].regions ||= {};
  return reviewState[id];
}

function sourceFor(choice) {
  if (choice === "KEEP CURRENT") return "现版";
  if (choice === "KEEP LEGACY") return "旧版";
  if (choice === "KEEP FUSE") return "融合版";
  return "待决定";
}

function regionMarkup(decision, region) {
  const state = pageState(decision.id).regions[region] || {};
  const options = ["KEEP CURRENT", "KEEP LEGACY", "KEEP FUSE", "CHANGE", "NEEDS REDESIGN"];
  return `<article class="region-card" data-region-page="${escapeHTML(decision.id)}" data-region-name="${escapeHTML(region)}" data-frozen="${state.frozen ? "true" : "false"}">
    <header class="region-card__header"><div><h4>${escapeHTML(displayText(region))}</h4><span class="region-source">当前来源：${escapeHTML(sourceFor(state.choice))}</span></div><span class="freeze-badge">${state.frozen ? "已冻结" : "待决定"}</span></header>
    <div class="region-options">${options.map((option) => `<label title="${escapeHTML(choiceExplanation(option))}"><input type="radio" name="region-${escapeHTML(decision.id)}-${escapeHTML(region)}" value="${option}" ${state.choice === option ? "checked" : ""} ${state.frozen ? "disabled" : ""}><span>${escapeHTML(displayChoice(option))}</span></label>`).join("")}</div>
    ${state.frozen ? `<button class="unfreeze-region" type="button">解除冻结</button>` : ""}
    <label class="region-notes">我的备注<textarea placeholder="只记录这个区域的保留或修改要求……">${escapeHTML(displayNote(state.notes))}</textarea></label>
  </article>`;
}

function fuseMarkup(decision) {
  return `<div class="section-block section-block--fuse" id="${decision.id}-fuse">
    <div class="section-heading section-heading--fuse"><div><h3>${escapeHTML(displayText(decision.candidateTitle || "融合版｜旧版基础 + 现版新增能力"))}</h3><p>下方证据来自真实 SwiftUI 构建与固定模拟器截图。</p></div><span class="fuse-evidence">候选版本：${escapeHTML(displayText(decision.candidateVersion || "融合候选版 V1"))}</span></div>
    <div class="image-track image-track--fuse">${decision.fuseVisuals.map((item) => visualMarkup(item, decision.title)).join("")}</div>
    <div class="fuse-grid"><article class="fuse-card"><span class="fuse-card__number">1</span><h4>旧版基础</h4>${listMarkup(decision.legacyBase)}</article><article class="fuse-card"><span class="fuse-card__number">2</span><h4>需要保留的现版新增能力</h4>${listMarkup(decision.currentAdditions)}</article><article class="fuse-card fuse-card--final"><span class="fuse-card__number">3</span><h4>建议的最终构图</h4>${listMarkup(decision.proposedFinal)}</article></div>
    <div class="candidate-status candidate-status--available">${escapeHTML(displayText(decision.candidateTitle || "候选版可用 · 真实实现"))}</div>
  </div>`;
}

function regionReviewMarkup(decision) {
  const state = pageState(decision.id);
  const frozen = decision.regions.filter((region) => state.regions[region]?.frozen).length;
  const approved = frozen === decision.regions.length;
  return `<div class="section-block region-review" data-region-summary="${decision.id}">
    <div class="section-heading"><div><h3>区域级审批与候选版冻结</h3><p>选择“保留”后立即冻结；只有明确“解除冻结”后才能在后续版本修改。</p></div><div class="region-totals"><span>${escapeHTML(displayText(decision.candidateVersion || "候选版"))}</span><span class="frozen-count">已冻结 ${frozen}</span><span class="pending-region-count">待修改 ${decision.regions.length - frozen}</span><strong class="final-approval ${approved ? "is-approved" : ""}">${approved ? "最终确认" : "尚未最终确认"}</strong></div></div>
    <div class="region-choice-help" aria-label="区域审批按钮说明">
      <span><strong>保留现版：</strong>采用当前 iOS 区域并冻结</span><span><strong>保留旧版：</strong>采用旧版 Web 区域并冻结</span><span><strong>保留融合版：</strong>采用当前融合候选区域并冻结</span><span><strong>需要修改：</strong>保留方向并继续调整</span><span><strong>重新设计：</strong>下一版重新设计该区域</span>
    </div>
    <div class="region-grid">${decision.regions.map((region) => regionMarkup(decision, region)).join("")}</div>
  </div>`;
}

function referenceSectionMarkup(decision) {
  return `<div class="section-block reference-section" data-reference-section="${escapeHTML(decision.id)}">
    <div class="section-heading reference-section__heading">
      <div>
        <h3>我的参考图</h3>
        <p>图片只保存在本机浏览器 IndexedDB，不会上传到 Taste Map、Production、云端或任何服务器。</p>
      </div>
      <span class="reference-count-badge" data-reference-count-for="${escapeHTML(decision.id)}">0 张</span>
    </div>
    <div class="reference-upload" data-reference-dropzone="${escapeHTML(decision.id)}" tabindex="0" role="button" aria-label="为${escapeHTML(displayText(decision.title))}上传或粘贴参考图片">
      <input class="reference-file-input" data-reference-file-input="${escapeHTML(decision.id)}" type="file" accept="image/png,image/jpeg,image/webp" multiple hidden>
      <div class="reference-upload__icon" aria-hidden="true">＋</div>
      <div class="reference-upload__copy">
        <strong>上传我的参考图</strong>
        <span>点击选择、拖拽多张 PNG / JPG / WEBP，或聚焦这里后按 ⌘V 粘贴。</span>
      </div>
      <div class="reference-upload__actions">
        <button class="reference-choose-button" type="button">选择图片</button>
        <button class="reference-paste-button" type="button">粘贴剪贴板图片</button>
      </div>
    </div>
    <p class="reference-status" data-reference-status="${escapeHTML(decision.id)}" aria-live="polite"></p>
    <div class="reference-list" data-reference-list="${escapeHTML(decision.id)}" aria-live="polite">
      <div class="reference-empty"><strong>还没有我的参考图</strong><span>Current、Legacy 和 FUSE 都不准确时，把 Lafayette 自己的图直接放在这里。</span></div>
    </div>
  </div>`;
}

function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function referenceImageURL(record) {
  if (!referenceObjectURLs.has(record.id)) referenceObjectURLs.set(record.id, URL.createObjectURL(record.blob));
  return referenceObjectURLs.get(record.id);
}

function referenceBadgeMarkup(record) {
  const badges = [];
  if (record.isFinal) badges.push('<strong class="reference-source-badge">LAFAYETTE 最终视觉参考</strong>');
  if (record.strength === "geometry") badges.push('<span class="reference-strength-badge">几何 / 构图 Source of Truth</span>');
  if (record.strength === "highFidelity") badges.push('<span class="reference-strength-badge">高度复刻参考</span>');
  return badges.join("");
}

function referenceRecordMarkup(decision, record, index) {
  const regions = new Set(record.regionIds || []);
  const title = record.title || record.filename;
  return `<article class="reference-card" data-reference-id="${escapeHTML(record.id)}" data-reference-item="${escapeHTML(decision.id)}">
    <header class="reference-card__header">
      <div><span class="reference-card__index">参考图 ${index + 1}</span><h4>${escapeHTML(title)}</h4><p>${escapeHTML(record.filename)} · ${formatFileSize(record.size)}</p></div>
      <div class="reference-card__badges">${referenceBadgeMarkup(record)}</div>
    </header>
    <button class="visual-card__button reference-card__preview" type="button" data-image-src="${escapeHTML(referenceImageURL(record))}" data-image-title="${escapeHTML(title)}" data-image-kind="Lafayette 用户参考图" data-image-caption="${escapeHTML(record.notes || referenceStrengthLabels[record.strength] || "Lafayette 用户参考图")}" aria-label="放大查看 Lafayette 参考图：${escapeHTML(title)}">
      <img src="${escapeHTML(referenceImageURL(record))}" alt="${escapeHTML(title)}">
    </button>
    <div class="reference-card__form">
      <label class="reference-field reference-field--wide"><span>参考图名称</span><input data-reference-field="title" value="${escapeHTML(title)}" maxlength="120"></label>
      <label class="reference-field"><span>用途</span><select data-reference-field="purpose">${Object.entries(referencePurposeLabels).map(([value, label]) => `<option value="${value}" ${record.purpose === value ? "selected" : ""}>${label}</option>`).join("")}</select></label>
      <label class="reference-field"><span>参考强度</span><select data-reference-field="strength">${Object.entries(referenceStrengthLabels).map(([value, label]) => `<option value="${value}" ${record.strength === value ? "selected" : ""}>${label}</option>`).join("")}</select></label>
      <label class="reference-final-toggle"><input type="checkbox" data-reference-field="isFinal" ${record.isFinal ? "checked" : ""}><span><strong>这是最终视觉方向</strong><small>显示“Lafayette 最终视觉参考”，后续实现必须先查看此图。</small></span></label>
      <fieldset class="reference-regions"><legend>绑定区域（可多选；整页参考可不选）</legend><div>${decision.regions.map((region) => `<label><input type="checkbox" data-reference-region="${escapeHTML(region)}" ${regions.has(region) ? "checked" : ""}><span>${escapeHTML(displayText(region))}</span></label>`).join("")}</div></fieldset>
      <label class="reference-field reference-field--notes"><span>这张图我主要想保留什么？</span><textarea data-reference-field="notes" placeholder="记录构图、层级、比例、留白、图片关系或必须保持的区域……">${escapeHTML(record.notes || "")}</textarea></label>
    </div>
    <footer class="reference-card__footer">
      <span class="reference-saved-at">本机保存 · ${escapeHTML(new Date(record.updatedAt || record.createdAt).toLocaleString("zh-CN"))}</span>
      <div>
        <label class="reference-replace-button">替换图片<input type="file" data-reference-replace accept="image/png,image/jpeg,image/webp" hidden></label>
        <button class="reference-delete-button" type="button">删除参考图</button>
      </div>
    </footer>
  </article>`;
}

function referencesForItem(itemId) {
  return referenceRecords.filter((record) => record.itemId === itemId);
}

function setReferenceStatus(itemId, message, tone = "") {
  const status = document.querySelector(`[data-reference-status="${CSS.escape(itemId)}"]`);
  if (!status) return;
  status.textContent = message;
  status.dataset.tone = tone;
}

async function refreshReferenceCache() {
  if (!referenceLibrary) return;
  referenceRecords = await referenceLibrary.listAll();
  decisions.forEach(renderReferenceList);
  updateReferenceProgress();
  bindLightboxItems();
}

function renderReferenceList(decision) {
  const list = document.querySelector(`[data-reference-list="${CSS.escape(decision.id)}"]`);
  if (!list) return;
  const records = referencesForItem(decision.id);
  document.querySelector(`[data-reference-count-for="${CSS.escape(decision.id)}"]`).textContent = `${records.length} 张`;
  list.innerHTML = records.length
    ? records.map((record, index) => referenceRecordMarkup(decision, record, index)).join("")
    : '<div class="reference-empty"><strong>还没有我的参考图</strong><span>Current、Legacy 和 FUSE 都不准确时，把 Lafayette 自己的图直接放在这里。</span></div>';
  bindReferenceRecordControls(decision, list);
}

function updateReferenceProgress() {
  document.querySelector("#reference-count").textContent = referenceRecords.length;
  document.querySelector("#reference-source-count").textContent = referenceRecords.filter((record) => record.isFinal || record.strength === "geometry").length;
}

async function importReferenceFiles(itemId, files, sourceLabel) {
  try {
    const added = await referenceLibrary.addFiles(itemId, files);
    await refreshReferenceCache();
    setReferenceStatus(itemId, added.length ? `已从${sourceLabel}保存 ${added.length} 张图片到本机参考图库。` : "没有检测到可用图片。", added.length ? "success" : "");
  } catch (error) {
    setReferenceStatus(itemId, error.message || "图片保存失败。", "error");
  }
}

async function pasteReferenceImages(itemId, event) {
  const clipboardItems = Array.from(event?.clipboardData?.items || []);
  const files = clipboardItems
    .filter((item) => item.kind === "file" && item.type.startsWith("image/"))
    .map((item, index) => {
      const file = item.getAsFile();
      return file && new File([file], `clipboard-${Date.now()}-${index + 1}.${file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg"}`, { type: file.type });
    })
    .filter(Boolean);
  if (!files.length) return false;
  event.preventDefault();
  await importReferenceFiles(itemId, files, "剪贴板");
  return true;
}

async function readClipboardImages(itemId) {
  if (!navigator.clipboard?.read) {
    setReferenceStatus(itemId, "当前浏览器需要先点击上传区域，再按 ⌘V 粘贴图片。", "error");
    document.querySelector(`[data-reference-dropzone="${CSS.escape(itemId)}"]`)?.focus();
    return;
  }
  try {
    const items = await navigator.clipboard.read();
    const files = [];
    for (const item of items) {
      for (const type of item.types.filter((value) => value.startsWith("image/"))) {
        const blob = await item.getType(type);
        files.push(new File([blob], `clipboard-${Date.now()}-${files.length + 1}.${type === "image/png" ? "png" : type === "image/webp" ? "webp" : "jpg"}`, { type }));
      }
    }
    if (!files.length) throw new Error("剪贴板里没有 PNG、JPG 或 WEBP 图片");
    await importReferenceFiles(itemId, files, "剪贴板");
  } catch (error) {
    setReferenceStatus(itemId, `${error.message || "无法读取剪贴板"}。也可以聚焦上传区域后按 ⌘V。`, "error");
  }
}

function bindReferenceUploadControls() {
  document.querySelectorAll("[data-reference-section]").forEach((section) => {
    const itemId = section.dataset.referenceSection;
    const input = section.querySelector("[data-reference-file-input]");
    const dropzone = section.querySelector("[data-reference-dropzone]");
    section.querySelector(".reference-choose-button").addEventListener("click", (event) => { event.stopPropagation(); input.click(); });
    section.querySelector(".reference-paste-button").addEventListener("click", (event) => { event.stopPropagation(); readClipboardImages(itemId); });
    input.addEventListener("change", async () => { await importReferenceFiles(itemId, input.files, "文件选择器"); input.value = ""; });
    dropzone.addEventListener("click", (event) => { if (!event.target.closest("button")) input.click(); });
    dropzone.addEventListener("keydown", (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); input.click(); } });
    ["dragenter", "dragover"].forEach((type) => dropzone.addEventListener(type, (event) => { event.preventDefault(); dropzone.dataset.dragging = "true"; }));
    ["dragleave", "dragend"].forEach((type) => dropzone.addEventListener(type, () => { delete dropzone.dataset.dragging; }));
    dropzone.addEventListener("drop", async (event) => { event.preventDefault(); delete dropzone.dataset.dragging; await importReferenceFiles(itemId, event.dataTransfer.files, "拖拽"); });
    dropzone.addEventListener("paste", (event) => pasteReferenceImages(itemId, event));
  });
}

function bindReferenceRecordControls(decision, list) {
  list.querySelectorAll(".reference-card").forEach((card) => {
    const id = card.dataset.referenceId;
    const saveFields = async () => {
      const regionIds = Array.from(card.querySelectorAll("[data-reference-region]:checked"), (input) => input.dataset.referenceRegion);
      const changes = {
        title: card.querySelector('[data-reference-field="title"]').value.trim() || "未命名参考图",
        purpose: card.querySelector('[data-reference-field="purpose"]').value,
        strength: card.querySelector('[data-reference-field="strength"]').value,
        isFinal: card.querySelector('[data-reference-field="isFinal"]').checked,
        notes: card.querySelector('[data-reference-field="notes"]').value,
        regionIds,
      };
      try {
        await referenceLibrary.update(id, changes);
        await refreshReferenceCache();
        setReferenceStatus(decision.id, "参考图用途、强度、区域和备注已保存在本机。", "success");
      } catch (error) {
        setReferenceStatus(decision.id, error.message || "参考图更新失败。", "error");
      }
    };
    card.querySelectorAll("[data-reference-field], [data-reference-region]").forEach((control) => control.addEventListener("change", saveFields));
    card.querySelector("[data-reference-replace]").addEventListener("change", async (event) => {
      const file = event.target.files?.[0];
      if (!file) return;
      try {
        URL.revokeObjectURL(referenceObjectURLs.get(id));
        referenceObjectURLs.delete(id);
        await referenceLibrary.replaceImage(id, file);
        await refreshReferenceCache();
        setReferenceStatus(decision.id, "参考图片已替换，原有用途、强度、区域与备注保持不变。", "success");
      } catch (error) {
        setReferenceStatus(decision.id, error.message || "替换图片失败。", "error");
      }
    });
    card.querySelector(".reference-delete-button").addEventListener("click", async (event) => {
      const button = event.currentTarget;
      if (button.dataset.confirmDelete !== "true") {
        button.dataset.confirmDelete = "true";
        button.textContent = "再次点击确认删除";
        window.setTimeout(() => { if (button.isConnected) { delete button.dataset.confirmDelete; button.textContent = "删除参考图"; } }, 3500);
        return;
      }
      try {
        await referenceLibrary.remove(id);
        URL.revokeObjectURL(referenceObjectURLs.get(id));
        referenceObjectURLs.delete(id);
        await refreshReferenceCache();
        setReferenceStatus(decision.id, "参考图已从本机图库删除。", "success");
      } catch (error) {
        setReferenceStatus(decision.id, error.message || "删除参考图失败。", "error");
      }
    });
  });
}

function decisionMarkup(decision, index) {
  const saved = pageState(decision.id);
  const choices = [
    { value: "Current", label: "现版" },
    { value: "Legacy", label: "旧版｜以旧版布局为基础" },
    { value: "FUSE", label: "融合版｜融合旧版与现版结构" },
    { value: "Option A", label: "方案 A" },
    { value: "Option B", label: "方案 B" },
    { value: "Needs redesign", label: "重新设计" },
  ];
  return `<section class="decision-card" id="${decision.id}" data-decision-id="${decision.id}" data-decided="${saved.decision ? "true" : "false"}">
    <header class="decision-card__header"><div class="decision-number">${String(index + 1).padStart(2, "0")}</div><div><h2>${escapeHTML(displayText(decision.title))}</h2><p class="decision-card__summary">${escapeHTML(displayText(decision.summary))}</p></div><span class="status-badge">${saved.decision ? `已选 · ${escapeHTML(displayDirection(saved.decision))}` : "待决定"}</span></header>
    <div class="section-block"><div class="section-heading"><h3>现版 iOS 与旧版 / 已确认历史参考</h3><p>所有旧版图片均来自 fb127e9 实际运行截图。</p></div><div class="image-track">${decision.visuals.map((item) => visualMarkup(item, decision.title)).join("")}</div></div>
    ${referenceSectionMarkup(decision)}
    ${fuseMarkup(decision)}
    <div class="section-block"><div class="recommendation"><div class="recommendation__mark">荐</div><div><strong>Codex 建议（不自动批准）</strong><p>${escapeHTML(displayText(decision.recommendation))}</p></div></div></div>
    ${regionReviewMarkup(decision)}
    <div class="decision-record"><h3>页面级选择</h3>
      <div class="decision-mode-definition">
        <article><strong>旧版</strong><p>历史版本整体布局、构图和信息架构作为视觉骨架；现版新增且已确认的能力以最小侵入方式嵌入。它不代表回滚代码、删除现版功能或恢复旧数据架构。</p></article>
        <article><strong>融合版</strong><p>旧版与现版都只取部分结构，形成新的融合构图。它不同于直接采用完整旧版页面骨架。</p></article>
      </div>
      ${decision.directionLocked ? `<p class="storage-note"><strong>${escapeHTML(window.visualApprovalPreviousRoundLabel || "第一轮")}方向已锁定：</strong>${escapeHTML(displayDirection(decision.direction))}。本轮请使用区域反馈和“我的备注”审批真实候选。</p>` : ""}
      <div class="decision-options">${choices.map((choice) => `<label class="decision-choice"><input type="radio" name="decision-${decision.id}" value="${choice.value}" ${saved.decision === choice.value ? "checked" : ""} ${decision.directionLocked ? "disabled" : ""}><span>${choice.label}</span></label>`).join("")}</div><label class="notes-label">页面备注<textarea data-notes-for="${decision.id}" placeholder="记录整个页面的总体决定……">${escapeHTML(saved.notes || "")}</textarea></label><p class="storage-note">记录仅保存在当前浏览器，不写入 Taste Map、Git、数据库或服务器。</p></div>
  </section>`;
}

function render() {
  document.querySelector("#decision-list").innerHTML = decisions.map(decisionMarkup).join("");
  document.querySelector("#jump-nav").innerHTML = decisions.map((decision, index) => `<a href="#${decision.id}" data-nav-id="${decision.id}" data-decided="${Boolean(pageState(decision.id).decision)}"><span class="jump-nav__number">${index + 1}</span><span>${escapeHTML(displayText(decision.shortTitle))}</span></a>`).join("");
  bindControls();
  bindReferenceUploadControls();
  decisions.forEach(renderReferenceList);
  bindLightboxItems();
  updateProgress();
  updateReferenceProgress();
}

function bindControls() {
  document.querySelectorAll(".decision-card").forEach((card) => {
    const id = card.dataset.decisionId;
    card.querySelectorAll(`input[name="decision-${id}"]`).forEach((input) => input.addEventListener("change", () => { pageState(id).decision = input.value; persistState(); updateDecisionStatus(card, id); updateProgress(); }));
    card.querySelector(`[data-notes-for="${id}"]`).addEventListener("input", (event) => { pageState(id).notes = event.target.value; persistState(); });
  });
  document.querySelectorAll(".region-card").forEach((card) => {
    const id = card.dataset.regionPage;
    const region = card.dataset.regionName;
    card.querySelectorAll('input[type="radio"]').forEach((input) => input.addEventListener("change", () => {
      const state = pageState(id); state.regions[region] ||= {}; state.regions[region].choice = input.value; state.regions[region].frozen = input.value.startsWith("KEEP "); persistState(); render(); document.querySelector(`#${id}-fuse`)?.scrollIntoView({ block: "start" });
    }));
    card.querySelector("textarea").addEventListener("input", (event) => { const state = pageState(id); state.regions[region] ||= {}; state.regions[region].notes = event.target.value; persistState(); });
    card.querySelector(".unfreeze-region")?.addEventListener("click", () => {
      const regionState = pageState(id).regions[region];
      regionState.frozen = false;
      regionState.choice = "";
      persistState();
      render();
      document.querySelector(`#${id}-fuse`)?.scrollIntoView({ block: "start" });
    });
  });
}

function updateDecisionStatus(card, id) {
  const value = pageState(id).decision;
  card.dataset.decided = value ? "true" : "false";
  card.querySelector(".status-badge").textContent = value ? `已选 · ${displayDirection(value)}` : "待决定";
  document.querySelector(`[data-nav-id="${id}"]`).dataset.decided = value ? "true" : "false";
}

function updateProgress() {
  const decided = decisions.filter((item) => pageState(item.id).decision).length;
  document.querySelector("#decided-count").textContent = decided;
  document.querySelector("#pending-count").textContent = decisions.length - decided;
  document.querySelector("#progress-meter-fill").style.width = `${(decided / decisions.length) * 100}%`;
  document.querySelector("#fuse-available-count").textContent = decisions.filter((item) => item.fuseVisuals.length).length;
  document.querySelector("#fuse-missing-count").textContent = decisions.filter((item) => !item.fuseVisuals.length).length;
  document.querySelector("#fuse-na-count").textContent = decisions.filter((item) => item.direction === "Current").length;
}

function bindLightboxItems() {
  lightboxItems = Array.from(document.querySelectorAll(".visual-card__button"));
  lightboxItems.forEach((button) => {
    if (button.dataset.lightboxBound === "true") return;
    button.dataset.lightboxBound = "true";
    button.addEventListener("click", () => openLightbox(lightboxItems.indexOf(button)));
  });
}
function openLightbox(index) { lightboxIndex = index; zoom = 1; updateLightbox(); document.querySelector("#lightbox").showModal(); }
function updateLightbox() { const item = lightboxItems[lightboxIndex]; if (!item) return; const image = document.querySelector("#lightbox-image"); image.src = item.dataset.imageSrc; image.alt = item.dataset.imageTitle; image.style.transform = `scale(${zoom})`; document.querySelector("#lightbox-kind").textContent = item.dataset.imageKind; document.querySelector("#lightbox-title").textContent = item.dataset.imageTitle; document.querySelector("#lightbox-caption").textContent = item.dataset.imageCaption; document.querySelector("#zoom-value").textContent = `${Math.round(zoom * 100)}%`; }
function changeZoom(delta) { zoom = Math.min(3, Math.max(0.5, Number((zoom + delta).toFixed(2)))); updateLightbox(); }
function moveLightbox(delta) { lightboxIndex = (lightboxIndex + delta + lightboxItems.length) % lightboxItems.length; zoom = 1; updateLightbox(); }

function referenceSummaryLines(decision) {
  const records = referencesForItem(decision.id);
  if (!records.length) return ["", "Lafayette 视觉参考：", "- 暂无"];
  const lines = ["", "Lafayette 视觉参考："];
  records.forEach((record, index) => {
    lines.push(`- ${index + 1}. ${record.title || record.filename}`);
    lines.push(`  原始文件：${record.filename}`);
    lines.push(`  用途：${referencePurposeLabels[record.purpose] || record.purpose}`);
    lines.push(`  参考强度：${referenceStrengthLabels[record.strength] || record.strength}`);
    lines.push(`  绑定区域：${(record.regionIds || []).map(displayText).join("、") || "整页 / 未单独绑定"}`);
    lines.push(`  Lafayette 最终视觉参考：${record.isFinal ? "是" : "否"}`);
    lines.push(`  我的备注：${record.notes?.trim() || "—"}`);
    if (record.isFinal || record.strength === "geometry" || record.strength === "highFidelity") {
      lines.push("  后续执行要求：必须先查看审批包中的这张图片，完成 Reference Decomposition 与 Layout Contract 后再实现，不得只根据文字摘要凭感觉重画。");
    }
  });
  return lines;
}

function approvalSummary() {
  const lines = [window.visualApprovalSummaryTitle || "# Taste Map — Lafayette 第二轮视觉审批记录", "", "视觉证据：真实 SwiftUI 构建 + 固定模拟器", ""];
  decisions.forEach((decision, index) => {
    const saved = pageState(decision.id);
    lines.push(`## ${index + 1}. ${displayText(decision.title)}`, "", `记录方向：${displayDirection(decision.direction, true)}`, `页面选择：${displayDirection(saved.decision, true)}`, `候选版本：${displayText(decision.candidateVersion || "—")}`, "", "旧版基础：");
    decision.legacyBase.forEach((item) => lines.push(`- ${displayText(item)}`));
    lines.push("", "需要保留的现版新增能力："); decision.currentAdditions.forEach((item) => lines.push(`- ${displayText(item)}`));
    lines.push("", "区域审批：");
    decision.regions.forEach((region) => { const state = saved.regions[region] || {}; lines.push(`- ${displayText(region)}：${displayChoice(state.choice, true)} | 当前来源：${sourceFor(state.choice)} | 状态：${state.frozen ? "已冻结" : "待决定"}`); if (state.notes?.trim()) lines.push(`  我的备注：${displayNote(state.notes.trim())}`); });
    lines.push(...referenceSummaryLines(decision));
    lines.push("", "页面备注：", saved.notes?.trim() || "—", "");
  });
  return lines.join("\n");
}

async function copySummary() {
  const button = document.querySelector("#copy-summary");
  const previous = button.textContent;
  try {
    referenceRecords = referenceLibrary ? await referenceLibrary.listAll() : [];
    const content = approvalSummary();
    try { await navigator.clipboard.writeText(content); } catch { const helper = document.createElement("textarea"); helper.value = content; helper.style.position = "fixed"; helper.style.opacity = "0"; document.body.append(helper); helper.select(); document.execCommand("copy"); helper.remove(); }
    button.textContent = "已复制审批摘要";
  } catch (error) {
    button.textContent = "复制失败，请重试";
  }
  window.setTimeout(() => { button.textContent = previous; }, 1600);
}

function parseStoredApproval(key) {
  try { return JSON.parse(localStorage.getItem(key) || "null"); } catch { return null; }
}

function approvalPackagePayload() {
  return {
    schema: "com.tastemap.lafayette.visual-approval",
    version: 1,
    activeRound: window.visualApprovalSummaryTitle || "当前视觉审批",
    activeStorageKey: storageKey,
    round2: parseStoredApproval("tastemap.visualApproval.round2"),
    current: structuredClone(reviewState),
    pages: decisions.map((decision) => ({
      id: decision.id,
      title: displayText(decision.title),
      direction: decision.direction,
      decision: pageState(decision.id).decision || "",
      candidateVersion: displayText(decision.candidateVersion || ""),
      notes: pageState(decision.id).notes || "",
      regions: decision.regions.map((region) => ({
        id: region,
        label: displayText(region),
        choice: pageState(decision.id).regions[region]?.choice || "",
        frozen: Boolean(pageState(decision.id).regions[region]?.frozen),
        notes: pageState(decision.id).regions[region]?.notes || "",
      })),
    })),
  };
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.hidden = true;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 2000);
}

async function exportApprovalPackage() {
  const button = document.querySelector("#export-approval");
  const previous = button.textContent;
  button.disabled = true;
  button.textContent = "正在生成审批包…";
  try {
    const result = await referenceLibrary.createApprovalPackage(approvalPackagePayload());
    button.dataset.exportBytes = String(result.blob.size);
    button.dataset.exportSignature = await result.blob.slice(0, 2).text();
    button.dataset.exportReferences = String(result.payload.references.length);
    downloadBlob(result.blob, "TasteMap-Lafayette-Visual-Approval.zip");
    button.textContent = `已导出 ${result.payload.references.length} 张参考图`;
  } catch (error) {
    button.textContent = "导出失败，请重试";
    console.error("Visual approval export failed", error);
  }
  window.setTimeout(() => { button.textContent = previous; button.disabled = false; }, 2200);
}

document.querySelector("#copy-summary").addEventListener("click", copySummary);
document.querySelector("#export-approval").addEventListener("click", exportApprovalPackage);
document.querySelector("#lightbox-close").addEventListener("click", () => document.querySelector("#lightbox").close());
document.querySelector("#zoom-out").addEventListener("click", () => changeZoom(-0.25));
document.querySelector("#zoom-in").addEventListener("click", () => changeZoom(0.25));
document.querySelector("#zoom-reset").addEventListener("click", () => { zoom = 1; updateLightbox(); });
document.querySelector("#lightbox-previous").addEventListener("click", () => moveLightbox(-1));
document.querySelector("#lightbox-next").addEventListener("click", () => moveLightbox(1));
document.querySelector("#fullscreen").addEventListener("click", async () => { const box = document.querySelector("#lightbox"); if (!document.fullscreenElement && box.requestFullscreen) await box.requestFullscreen(); else if (document.exitFullscreen) await document.exitFullscreen(); });
document.addEventListener("keydown", (event) => { if (!document.querySelector("#lightbox").open) return; if (event.key === "ArrowLeft") moveLightbox(-1); if (event.key === "ArrowRight") moveLightbox(1); if (event.key === "+" || event.key === "=") changeZoom(0.25); if (event.key === "-") changeZoom(-0.25); });
window.addEventListener("beforeunload", () => referenceObjectURLs.forEach((url) => URL.revokeObjectURL(url)));

render();
refreshReferenceCache().catch((error) => {
  console.error("Visual reference library failed to load", error);
  decisions.forEach((decision) => setReferenceStatus(decision.id, "本机参考图库暂时无法读取，请刷新页面重试。", "error"));
});
