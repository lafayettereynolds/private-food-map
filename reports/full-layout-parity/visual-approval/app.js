const LEGACY = "../legacy-reference-screenshots/";
const FUSE = "fuse-candidates/";
const ATLAS = "../final-atlas/";

const decisions = window.round2Decisions || [
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

const storageKey = "tastemap.visualApproval.round2";
let reviewState = readState();
let lightboxItems = [];
let lightboxIndex = 0;
let zoom = 1;

function escapeHTML(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");
}

function readState() {
  try {
    const current = JSON.parse(localStorage.getItem(storageKey) || "null");
    if (current) return current;
    return structuredClone(window.round2InitialState || {});
  } catch { return {}; }
}

function persistState() {
  try { localStorage.setItem(storageKey, JSON.stringify(reviewState)); } catch { /* session-only fallback */ }
}

function visualMarkup(visual, decisionTitle) {
  const normalized = visual.kind.toLowerCase();
  const kindClass = normalized.includes("legacy") ? " visual-card__kind--legacy" : normalized.includes("fuse") ? " visual-card__kind--fuse" : normalized.includes("reference") ? " visual-card__kind--reference" : "";
  return `<article class="visual-card">
    <div class="visual-card__meta"><div class="visual-card__title">${escapeHTML(visual.title)}</div><span class="visual-card__kind${kindClass}">${escapeHTML(visual.kind)}</span></div>
    <button class="visual-card__button" type="button" data-image-src="${escapeHTML(visual.src)}" data-image-title="${escapeHTML(visual.title)}" data-image-kind="${escapeHTML(visual.kind)}" data-image-caption="${escapeHTML(visual.caption)}" aria-label="放大查看：${escapeHTML(decisionTitle)}，${escapeHTML(visual.title)}">
      <img src="${escapeHTML(visual.src)}" alt="${escapeHTML(visual.title)}" loading="lazy">
    </button><p class="visual-card__caption">${escapeHTML(visual.caption)}</p></article>`;
}

function listMarkup(items) { return `<ul>${items.map((item) => `<li>${escapeHTML(item)}</li>`).join("")}</ul>`; }

function pageState(id) {
  reviewState[id] ||= {};
  reviewState[id].regions ||= {};
  return reviewState[id];
}

function sourceFor(choice) {
  if (choice === "KEEP CURRENT") return "Current";
  if (choice === "KEEP LEGACY") return "Legacy";
  if (choice === "KEEP FUSE") return "FUSE";
  return "Pending";
}

function regionMarkup(decision, region) {
  const state = pageState(decision.id).regions[region] || {};
  const options = ["KEEP CURRENT", "KEEP LEGACY", "KEEP FUSE", "CHANGE", "NEEDS REDESIGN"];
  return `<article class="region-card" data-region-page="${escapeHTML(decision.id)}" data-region-name="${escapeHTML(region)}" data-frozen="${state.frozen ? "true" : "false"}">
    <header class="region-card__header"><div><h4>${escapeHTML(region)}</h4><span class="region-source">Source: ${escapeHTML(sourceFor(state.choice))}</span></div><span class="freeze-badge">${state.frozen ? "FROZEN" : "OPEN"}</span></header>
    <div class="region-options">${options.map((option) => `<label><input type="radio" name="region-${escapeHTML(decision.id)}-${escapeHTML(region)}" value="${option}" ${state.choice === option ? "checked" : ""} ${state.frozen ? "disabled" : ""}><span>${option}</span></label>`).join("")}</div>
    ${state.frozen ? `<button class="unfreeze-region" type="button">解除冻结后再修改</button>` : ""}
    <label class="region-notes">Lafayette Notes<textarea placeholder="只记录这个区域的保留或修改要求……">${escapeHTML(state.notes || "")}</textarea></label>
  </article>`;
}

function fuseMarkup(decision) {
  return `<div class="section-block section-block--fuse" id="${decision.id}-fuse">
    <div class="section-heading section-heading--fuse"><div><h3>${escapeHTML(decision.candidateTitle || "FUSE｜Legacy Base + Current Additions")}</h3><p>下方证据来自真实 SwiftUI build 与固定 Simulator 截图。</p></div><span class="fuse-evidence">Candidate Version: ${escapeHTML(decision.candidateVersion || "FUSE V1")}</span></div>
    <div class="image-track image-track--fuse">${decision.fuseVisuals.map((item) => visualMarkup(item, decision.title)).join("")}</div>
    <div class="fuse-grid"><article class="fuse-card"><span class="fuse-card__number">1</span><h4>Legacy Base</h4>${listMarkup(decision.legacyBase)}</article><article class="fuse-card"><span class="fuse-card__number">2</span><h4>Current Additions to Preserve</h4>${listMarkup(decision.currentAdditions)}</article><article class="fuse-card fuse-card--final"><span class="fuse-card__number">3</span><h4>Proposed Final Composition</h4>${listMarkup(decision.proposedFinal)}</article></div>
    <div class="candidate-status candidate-status--available">${escapeHTML(decision.candidateTitle || "CANDIDATE AVAILABLE · REAL IMPLEMENTATION")}</div>
  </div>`;
}

function regionReviewMarkup(decision) {
  const state = pageState(decision.id);
  const frozen = decision.regions.filter((region) => state.regions[region]?.frozen).length;
  const approved = frozen === decision.regions.length;
  return `<div class="section-block region-review" data-region-summary="${decision.id}">
    <div class="section-heading"><div><h3>区域级审批与 Candidate Freeze</h3><p>KEEP 后立即冻结；只有明确“解除冻结”后才能在后续版本修改。</p></div><div class="region-totals"><span>${escapeHTML(decision.candidateVersion || "Candidate")}</span><span class="frozen-count">已冻结 ${frozen}</span><span class="pending-region-count">待修改 ${decision.regions.length - frozen}</span><strong class="final-approval ${approved ? "is-approved" : ""}">${approved ? "APPROVED FINAL" : "NOT FINAL"}</strong></div></div>
    <div class="region-grid">${decision.regions.map((region) => regionMarkup(decision, region)).join("")}</div>
  </div>`;
}

function decisionMarkup(decision, index) {
  const saved = pageState(decision.id);
  const choices = [
    { value: "Current", label: "Current" },
    { value: "Legacy", label: "Legacy｜Use Legacy Layout as Base" },
    { value: "FUSE", label: "FUSE｜Legacy + Current Structural Fusion" },
    { value: "Option A", label: "Option A" },
    { value: "Option B", label: "Option B" },
    { value: "Needs redesign", label: "Needs redesign" },
  ];
  return `<section class="decision-card" id="${decision.id}" data-decision-id="${decision.id}" data-decided="${saved.decision ? "true" : "false"}">
    <header class="decision-card__header"><div class="decision-number">${String(index + 1).padStart(2, "0")}</div><div><h2>${escapeHTML(decision.title)}</h2><p class="decision-card__summary">${escapeHTML(decision.summary)}</p></div><span class="status-badge">${saved.decision ? `已选 · ${escapeHTML(saved.decision)}` : "待决定"}</span></header>
    <div class="section-block"><div class="section-heading"><h3>Current iOS vs Legacy / Approved Reference</h3><p>所有 Legacy 图均来自 fb127e9 实际运行截图。</p></div><div class="image-track">${decision.visuals.map((item) => visualMarkup(item, decision.title)).join("")}</div></div>
    ${fuseMarkup(decision)}
    <div class="section-block"><div class="recommendation"><div class="recommendation__mark">C</div><div><strong>Codex 推荐（不自动批准）</strong><p>${escapeHTML(decision.recommendation)}</p></div></div></div>
    ${regionReviewMarkup(decision)}
    <div class="decision-record"><h3>页面级选择</h3>
      <div class="decision-mode-definition">
        <article><strong>Legacy</strong><p>历史版本整体布局、构图和信息架构作为视觉骨架；Current 新增且已确认的能力以最小侵入方式嵌入。它不代表回滚代码、删除 Current 功能或恢复旧数据架构。</p></article>
        <article><strong>FUSE</strong><p>Legacy 与 Current 都只取部分结构，形成新的融合构图。它不同于直接采用完整 Legacy 页面骨架。</p></article>
      </div>
      ${decision.directionLocked ? `<p class="storage-note"><strong>Round 1 direction 已锁定：</strong>${escapeHTML(decision.direction)}。本轮请使用区域反馈和 Notes 审批真实候选。</p>` : ""}
      <div class="decision-options">${choices.map((choice) => `<label class="decision-choice"><input type="radio" name="decision-${decision.id}" value="${choice.value}" ${saved.decision === choice.value ? "checked" : ""} ${decision.directionLocked ? "disabled" : ""}><span>${choice.label}</span></label>`).join("")}</div><label class="notes-label">Page Notes<textarea data-notes-for="${decision.id}" placeholder="记录整个页面的总体决定……">${escapeHTML(saved.notes || "")}</textarea></label><p class="storage-note">记录仅保存在当前浏览器，不写入 App、Git、数据库或服务器。</p></div>
  </section>`;
}

function render() {
  document.querySelector("#decision-list").innerHTML = decisions.map(decisionMarkup).join("");
  document.querySelector("#jump-nav").innerHTML = decisions.map((decision, index) => `<a href="#${decision.id}" data-nav-id="${decision.id}" data-decided="${Boolean(pageState(decision.id).decision)}"><span class="jump-nav__number">${index + 1}</span><span>${escapeHTML(decision.shortTitle)}</span></a>`).join("");
  bindControls(); bindLightboxItems(); updateProgress();
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
  card.querySelector(".status-badge").textContent = value ? `已选 · ${value}` : "待决定";
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
  lightboxItems.forEach((button, index) => button.addEventListener("click", () => openLightbox(index)));
}
function openLightbox(index) { lightboxIndex = index; zoom = 1; updateLightbox(); document.querySelector("#lightbox").showModal(); }
function updateLightbox() { const item = lightboxItems[lightboxIndex]; if (!item) return; const image = document.querySelector("#lightbox-image"); image.src = item.dataset.imageSrc; image.alt = item.dataset.imageTitle; image.style.transform = `scale(${zoom})`; document.querySelector("#lightbox-kind").textContent = item.dataset.imageKind; document.querySelector("#lightbox-title").textContent = item.dataset.imageTitle; document.querySelector("#lightbox-caption").textContent = item.dataset.imageCaption; document.querySelector("#zoom-value").textContent = `${Math.round(zoom * 100)}%`; }
function changeZoom(delta) { zoom = Math.min(3, Math.max(0.5, Number((zoom + delta).toFixed(2)))); updateLightbox(); }
function moveLightbox(delta) { lightboxIndex = (lightboxIndex + delta + lightboxItems.length) % lightboxItems.length; zoom = 1; updateLightbox(); }

function approvalSummary() {
  const lines = ["# Taste Map — Lafayette Visual Approval Round 2", "", "Evidence: real SwiftUI build + fixed Simulator", ""];
  decisions.forEach((decision, index) => {
    const saved = pageState(decision.id);
    lines.push(`## ${index + 1}. ${decision.title}`, "", `Recorded direction: ${decision.direction || "PENDING"}`, `Decision: ${saved.decision || "PENDING"}`, `Candidate: ${decision.candidateVersion || "—"}`, "", "Legacy base:");
    decision.legacyBase.forEach((item) => lines.push(`- ${item}`));
    lines.push("", "Current additions:"); decision.currentAdditions.forEach((item) => lines.push(`- ${item}`));
    lines.push("", "Region approvals:");
    decision.regions.forEach((region) => { const state = saved.regions[region] || {}; lines.push(`- ${region}: ${state.choice || "PENDING"} | Source: ${sourceFor(state.choice)} | Frozen: ${state.frozen ? "YES" : "NO"}`); if (state.notes?.trim()) lines.push(`  Notes: ${state.notes.trim()}`); });
    lines.push("", "Notes:", saved.notes?.trim() || "—", "");
  });
  return lines.join("\n");
}

async function copySummary() {
  const button = document.querySelector("#copy-summary"); const content = approvalSummary();
  try { await navigator.clipboard.writeText(content); } catch { const helper = document.createElement("textarea"); helper.value = content; helper.style.position = "fixed"; helper.style.opacity = "0"; document.body.append(helper); helper.select(); document.execCommand("copy"); helper.remove(); }
  const previous = button.textContent; button.textContent = "已复制审批摘要"; window.setTimeout(() => { button.textContent = previous; }, 1600);
}

document.querySelector("#copy-summary").addEventListener("click", copySummary);
document.querySelector("#lightbox-close").addEventListener("click", () => document.querySelector("#lightbox").close());
document.querySelector("#zoom-out").addEventListener("click", () => changeZoom(-0.25));
document.querySelector("#zoom-in").addEventListener("click", () => changeZoom(0.25));
document.querySelector("#zoom-reset").addEventListener("click", () => { zoom = 1; updateLightbox(); });
document.querySelector("#lightbox-previous").addEventListener("click", () => moveLightbox(-1));
document.querySelector("#lightbox-next").addEventListener("click", () => moveLightbox(1));
document.querySelector("#fullscreen").addEventListener("click", async () => { const box = document.querySelector("#lightbox"); if (!document.fullscreenElement && box.requestFullscreen) await box.requestFullscreen(); else if (document.exitFullscreen) await document.exitFullscreen(); });
document.addEventListener("keydown", (event) => { if (!document.querySelector("#lightbox").open) return; if (event.key === "ArrowLeft") moveLightbox(-1); if (event.key === "ArrowRight") moveLightbox(1); if (event.key === "+" || event.key === "=") changeZoom(0.25); if (event.key === "-") changeZoom(-0.25); });

render();
