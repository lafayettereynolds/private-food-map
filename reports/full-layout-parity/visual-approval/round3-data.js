const R3_FORMAL = "round-3/formal/";
const R3_CANDIDATE = "round-3/candidates/";
const R3_ATLAS = "../final-atlas/";
const R3_WEB_REFERENCE = "../../full-product-parity-assets/";
const R4_CANDIDATE = "round-4/candidates/";
const R4_CLEAN = "round-4/clean/";
const R4_REFERENCE = "round-4/reference/";

function r3v(kind, title, src, caption, cleanSrc = "") {
  return cleanSrc ? { kind, title, src, caption, cleanSrc } : { kind, title, src, caption };
}

const coreHumanApprovalDecisions = [
  {
    id: "my-map-list",
    title: "我的地图 / 我的列表｜Lafayette 人工审批",
    shortTitle: "我的地图 / 列表",
    direction: "FUSE",
    directionLocked: false,
    candidateTitle: "当前融合实现｜尚未人工批准",
    candidateVersion: "当前真实实现",
    summary: "此前 Task C 的 Visual PASS / CLOSED 只代表自动化和 Codex 审计通过，不代表 Lafayette 已批准。标题、范围、筛选、Marker、列表和状态保持全部重新开放人工审批。",
    visuals: [
      r3v("现版 iOS｜真实截图", "当前我的地图", R3_ATLAS + "task-04-map-after.png", "当前正式 iOS：标题、一级范围、筛选栏、独立餐厅标记和添加餐厅入口。"),
      r3v("现版 iOS｜真实截图", "当前我的列表", R3_ATLAS + "legacy-fusion-02-my-list-images.png", "当前正式 iOS 列表状态；使用统一餐厅图片策略。"),
      r3v("旧版 Web｜真实截图", "历史我的地图", R3_WEB_REFERENCE + "web-map-before.jpg", "旧 Web 实际页面截图，不是 AI 图或拼接图。"),
      r3v("旧版 Web｜真实截图", "历史我的列表", R3_WEB_REFERENCE + "web-list-before.jpg", "旧 Web 实际列表截图，作为布局和密度证据。")
    ],
    fuseVisuals: [
      r3v("融合候选版｜当前真实实现", "地图融合候选：自然重叠与真实图片", R3_ATLAS + "legacy-fusion-rich-natural-markers.png", "当前正式实现已经融合历史重叠层级与现版独立 Marker、真实图片和稳定身份；仍需 Lafayette 亲自批准。"),
      r3v("融合候选版｜当前真实实现", "列表融合候选：真实餐厅图片", R3_ATLAS + "legacy-fusion-02-my-list-images.png", "当前正式列表实现；候选截图不等于自动批准。")
    ],
    legacyBase: ["地图为第一屏主视觉，顶部控制克制。", "去过、想吃、推荐与筛选状态在地图/列表间保持。", "餐厅标记允许自然重叠，高评分优先置于上层。"],
    currentAdditions: ["我的地图 / 我的列表标题与相邻图标作为唯一切换入口。", "去过 / 想吃 / 推荐、共享筛选与排序、用户头像位置、独立 Restaurant ID。", "无数字聚合；selected → rating → visit count → stable ID；真实餐厅图片优先。"],
    proposedFinal: ["顶部留白 → 居中标题与切换图标 → 三个一级范围 → 紧凑筛选栏 → 地图或列表。", "地图与列表共享同一查询状态；添加餐厅入口不遮挡地图、标记或 Tab Bar。"],
    recommendation: "建议逐区对照现版和旧版后再决定。此前 CLOSED 状态在本工具中没有审批效力。",
    regions: ["顶部标题与地图 / 列表切换", "去过 / 想吃 / 推荐", "筛选栏", "餐厅标记与重叠层级", "用户位置", "选中餐厅与预览", "添加餐厅按钮", "我的列表条目", "地图 / 列表状态保持", "空白 / 加载 / 错误"]
  },
  {
    id: "discovery-core",
    title: "发现｜完整页面人工审批",
    shortTitle: "发现",
    direction: "FUSE",
    directionLocked: false,
    candidateTitle: "当前融合实现｜尚未人工批准",
    candidateVersion: "当前真实实现",
    summary: "发现页的五个一级入口、共享筛选和 Activity Card 曾被自动标为 PASS，但页面与每个内容区域均未获得 Lafayette 区域级批准。",
    visuals: [
      r3v("现版 iOS｜真实截图", "为你推荐", R3_ATLAS + "final-atlas-discovery-for-you.png", "当前正式为你推荐内容态。"),
      r3v("现版 iOS｜真实截图", "关注动态", R3_ATLAS + "p3-d-community-feed.png", "当前正式 Activity Card、社交动作和餐厅导航。"),
      r3v("现版 iOS｜真实截图", "同味之选", R3_ATLAS + "task-02-same-taste-content-after.png", "当前正式同味内容态。"),
      r3v("现版 iOS｜真实截图", "最新", R3_ATLAS + "final-atlas-discovery-latest.png", "当前正式最新动态。"),
      r3v("现版 iOS｜真实截图", "趋势", R3_ATLAS + "final-atlas-discovery-trending.png", "当前正式趋势内容。"),
      r3v("现版 iOS｜真实截图", "错误与重试", R3_ATLAS + "final-atlas-visual-qa-discovery-error.png", "当前可恢复错误状态。"),
      r3v("旧版 Web｜真实截图", "历史发现页", R3_WEB_REFERENCE + "web-discovery-before.jpg", "旧 Web 实际发现页面截图，不是 AI 图或拼接图。")
    ],
    fuseVisuals: [
      r3v("融合候选版｜当前真实实现", "发现融合候选：餐厅真实图片", R3_ATLAS + "legacy-fusion-02-discovery-images.png", "当前实现融合旧版发现层级与现版真实图片、Activity rating、Social 和离线能力；仍待 Lafayette 审批。")
    ],
    legacyBase: ["关注 / 为你推荐 / 同味之选 / 最新 / 趋势是同一级产品入口。", "用户、餐厅、具体到访评分和互动动作在同一内容证据中呈现。"],
    currentAdditions: ["共享 TasteMapPrimaryTabBar 与筛选栏。", "服务端 Like/Comment、分享、举报/拉黑、离线缓存、分页与重试。", "具体 Visit rating；nil 显示未评分；统一餐厅图片 renderer。"],
    proposedFinal: ["居中发现标题 → 五个等宽一级入口 → 紧凑筛选栏 → 当前入口的真实内容状态。", "Activity Card 保持用户/时间、餐厅图文、具体到访评分、互动与餐厅动作的清楚分组。"],
    recommendation: "建议按 11 个区域分别审批；不要用自动测试覆盖 Lafayette 的布局判断。",
    regions: ["标题", "五个一级 Tab", "筛选栏", "动态卡片", "用户 / 时间", "餐厅图片 / 信息", "到访评分", "点赞 / 评论 / 更多", "餐厅操作", "同味之选内容", "空白 / 加载 / 错误"]
  },
  {
    id: "add-restaurant-nearby",
    title: "添加餐厅 / Nearby｜完整流程人工审批",
    shortTitle: "添加餐厅 / Nearby",
    direction: "FUSE",
    directionLocked: false,
    candidateTitle: "当前融合实现｜尚未人工批准",
    candidateVersion: "当前真实实现",
    summary: "Search、Nearby、Manual Add、Share Import、结果、预览和动作都重新进入人工审批；真实 GPS 和数据语义保持现版能力，但不自动决定页面构图。",
    visuals: [
      r3v("现版 iOS｜真实截图", "当前 Nearby", R3_ATLAS + "full-parity-add-restaurant-nearby-after.png", "当前正式 Nearby 与定位状态。"),
      r3v("现版 iOS｜真实截图", "当前搜索候选预览", R3_ATLAS + "product-ux-restaurant-search-preview.png", "当前正式搜索结果与候选预览。"),
      r3v("现版 iOS｜真实截图", "当前手动添加预览", R3_ATLAS + "product-ux-manual-restaurant-preview.png", "当前正式 Manual Add 候选确认。"),
      r3v("现版 iOS｜真实截图", "当前外部分享识别", R3_ATLAS + "product-ux-external-share-recognition.png", "当前正式 Share Import 识别状态。"),
      r3v("旧版 Web｜真实截图", "历史添加餐厅", R3_WEB_REFERENCE + "web-add-restaurant-before.jpg", "旧 Web 实际添加餐厅页面截图，不是 AI 图或拼接图。")
    ],
    fuseVisuals: [
      r3v("融合候选版｜当前真实实现", "添加餐厅融合候选", R3_ATLAS + "full-parity-add-restaurant-nearby-after.png", "当前实现融合旧版入口层级与现版 fresh CLLocation、跨 provider identity、Share Import 和标准预览；仍待 Lafayette 审批。")
    ],
    legacyBase: ["Search、Nearby 和 Manual Add 是清楚、可找到的正式入口。", "结果先展示餐厅信息，再由用户明确选择想去或记录到访。"],
    currentAdditions: ["fresh CLLocation、时间戳/精度校验、Reduced Accuracy、3km 与真实距离排序。", "Apple Maps / AMap / URL / 分享文本、provider-neutral identity、显式去重确认。", "Share Extension ingestion 与全局 Restaurant Detail transition。"],
    proposedFinal: ["Header → Search → Nearby → Manual Add；Share Import 通过正式入口进入同一候选预览。", "Search/Nearby 结果和预览不重复维护第二套餐厅详情。"],
    recommendation: "建议逐区审查入口顺序和信息密度；GPS 正确性继续由真实设备验证，不用视觉选择替代。",
    regions: ["顶部", "搜索", "附近餐厅", "手动添加", "分享导入", "搜索结果", "附近结果", "餐厅预览", "想去 / 记录到访操作", "餐厅详情过渡"]
  },
  {
    id: "restaurant-detail-global",
    title: "餐厅详情｜全局唯一主体人工审批",
    shortTitle: "餐厅详情",
    direction: "FUSE",
    directionLocked: false,
    candidateTitle: "当前融合实现｜尚未人工批准",
    candidateVersion: "当前真实实现",
    summary: "全局唯一主体与跨入口复用已经自动验证，但 Hero、操作、基础信息、评分、照片和到访内容的最终构图仍需 Lafayette 亲自冻结。",
    visuals: [
      r3v("现版 iOS｜真实截图", "当前餐厅详情顶部", R3_ATLAS + "task-04-restaurant-detail-after.png", "当前正式 Hero、名称、操作与基础信息。"),
      r3v("现版 iOS｜真实截图", "当前本地餐厅下游内容", R3_ATLAS + "global-restaurant-detail-local-after.png", "当前正式用户照片、到访概览和历史。"),
      r3v("现版 iOS｜真实截图", "当前远程入口主体", R3_ATLAS + "global-restaurant-detail-remote-after.png", "远程/社区入口使用相同 Restaurant Detail 主体。"),
      r3v("旧版 Web｜真实截图", "历史餐厅详情", R3_WEB_REFERENCE + "web-restaurant-detail-before.jpg", "旧 Web 实际餐厅详情截图，不是 AI 图或拼接图。")
    ],
    fuseVisuals: [
      r3v("融合候选版｜当前真实实现", "餐厅详情融合候选：真实图片", R3_ATLAS + "legacy-fusion-02-restaurant-detail-image.png", "当前全局统一主体融合旧版信息顺序与现版真实图片、评分样本、PhotoAsset 和多入口；仍待 Lafayette 审批。")
    ],
    legacyBase: ["Hero → 城市/状态 → 名称 → 操作 → 地址/价格/电话/营业时间/导航。", "四圆评分、用户实拍、我的到访概览与历史保持固定层级。"],
    currentAdditions: ["RestaurantDetailView / RestaurantDetailStandardBody 全局唯一主体。", "本地/公共/provider 图片优先级、nil/sample 诚实评分、Dish/Photo 与详细评分。", "entrySource 只影响返回、权限和分析，不改变主体 UI。"],
    proposedFinal: ["使用一套主体覆盖地图、搜索、Nearby、发现、社交、食单、轮盘、分析与分享入口。", "所有入口对同一家餐厅呈现相同的 Hero 到下游内容顺序。"],
    recommendation: "建议按七个主体区域审批；跨入口一致性属于不可删能力，不因视觉选择分叉页面。",
    regions: ["Hero", "名称与操作", "基础信息", "评分参考", "用户实拍", "到访概览", "下游内容"]
  },
  {
    id: "roulette-core",
    title: "今天吃什么 / Roulette｜完整页面人工审批",
    shortTitle: "今天吃什么",
    direction: "FUSE",
    directionLocked: false,
    candidateTitle: "当前融合实现｜尚未人工批准",
    candidateVersion: "当前真实实现",
    summary: "轮盘几何、候选池和算法虽然已通过自动验收，但指针、中心、分区、候选管理、图片和结果构图尚未获得 Lafayette 区域级批准。",
    visuals: [
      r3v("现版 iOS｜真实截图", "当前大型候选池", R3_ATLAS + "p4-g-large-candidate-pool.png", "当前正式候选 chips、轮盘和十家候选状态。"),
      r3v("现版 iOS｜真实截图", "当前抽签结果", R3_ATLAS + "p4-g-roulette-result.png", "当前正式结果交互。"),
      r3v("现版 iOS｜真实截图", "当前真实餐厅图片", R3_ATLAS + "legacy-fusion-02-roulette-images.png", "当前统一餐厅图片 renderer。"),
      r3v("旧版 Web｜真实截图", "历史轮盘顶部", R3_WEB_REFERENCE + "web-roulette-reference-top-module-6.png", "旧 Web 实际轮盘截图，不是 AI 图或拼接图。"),
      r3v("旧版 Web｜真实截图", "历史轮盘完整页面", R3_WEB_REFERENCE + "web-roulette-reference-module-6.png", "旧 Web 实际候选管理与轮盘页面截图。")
    ],
    fuseVisuals: [
      r3v("融合候选版｜当前真实实现", "轮盘融合候选", R3_ATLAS + "p4-g-large-candidate-pool.png", "当前实现融合历史 wheel geometry 与现版稳定 ID、统一图片、筛选和 Manual Add；仍待 Lafayette 审批。")
    ],
    legacyBase: ["清楚的 pointer、center、5–10 个 segment、候选 chips 和管理面板。", "未填 segment 显示“+ 添加更多餐厅”，不冒充真实候选。"],
    currentAdditions: ["候选 chip、轮盘 segment 和结果使用同一个 stable Restaurant pool。", "真实餐厅图片、名称、城市、评分、最多 10 家、至少 2 家和均匀随机。", "候选管理连接正式 Restaurant 与 Manual Add，不创建临时假餐厅。"],
    proposedFinal: ["Header / 候选管理 → 候选 chips → wheel / pointer / center → spin action → 结果。", "视觉构图不得让结果、候选或空 slot 与实际抽签池不一致。"],
    recommendation: "建议逐区批准轮盘几何与候选管理；自动随机测试不能代替视觉审批。",
    regions: ["顶部", "候选概览", "轮盘几何", "指针与中心", "餐厅分区", "空白分区", "候选管理", "抽签结果", "餐厅图片", "空白 / 错误"]
  }
];

window.round3Decisions = [...coreHumanApprovalDecisions, ...structuredClone(window.round2Decisions || [])];
const r3ByID = Object.fromEntries(window.round3Decisions.map((item) => [item.id, item]));

Object.assign(r3ByID["profile-density"], {
  title: "我的页面｜融合候选版 V4",
  candidateTitle: "融合候选版 V4｜真实 SwiftUI 实现",
  candidateVersion: "融合候选版 V4",
  summary: "只重做核心入口：今天吃什么与我的口味档案使用等宽、等高、同构的双入口。关注/粉丝、去过/想去/总消费与其余七个已确认区域继续冻结。",
  fuseVisuals: [
    r3v("融合候选版｜真实实现", "我的页面融合候选版 V4", R4_CANDIDATE + "profile-fuse-v4.png", "独立候选分支真实 SwiftUI：只把核心入口收口为对称的双入口；其他冻结区域没有重画。", R4_CLEAN + "profile-fuse-v4-clean.png")
  ],
  proposedFinal: ["旧版紧凑身份骨架不变。", "姓名下方呈现关注与粉丝；主统计仅保留去过、想去、总消费。", "核心入口保持两项同级、等宽、等高、相同图标与箭头节奏；其余冻结区域保持既有构图。"],
  recommendation: "本轮仅审批核心入口 V4；其余七个已冻结区域继续保持，不因 V4 重新开放。"
});

Object.assign(r3ByID["visit-editor-density"], {
  title: "到访记录｜Lafayette 已确认 · 正式实现",
  direction: "FUSE",
  directionLocked: true,
  candidateTitle: "最终确认｜正式 SwiftUI 实现",
  candidateVersion: "最终确认",
  summary: "全部八个区域已经明确批准为 Legacy 连续日记式布局；Current 空值、离线、菜品/照片、同步和唯一保存语义继续保留。",
  fuseVisuals: [
    r3v("最终 iOS｜真实实现", "到访记录：菜品、照片与详细评分", R3_FORMAL + "visit-editor-rich-approved.png", "正式分支真实 UI 测试截图；字段直接展示，不依赖展开按钮。"),
    r3v("最终 iOS｜真实实现", "到访记录：直接可点评分与体验", R3_FORMAL + "visit-editor-direct-ratings-approved.png", "详细评分和体验选项在连续表单中直接可见、可点，保存动作继续复用正式实现。")
  ],
  proposedFinal: ["餐厅上下文 → 核心体验 → 评分 → 菜品与照片 → 用餐情境 → 备注 → 保存。", "视觉与密度完全采用旧版基础；不恢复六个废弃字段，不修改 nil/offline/save 业务语义。"],
  recommendation: "已正式落地并由 UI 回归验证；不再作为待选候选。"
});

Object.assign(r3ByID["dish-photo-composition"], {
  candidateTitle: "最终确认｜旧版布局基础",
  candidateVersion: "最终确认",
  summary: "八个区域全部保留旧版并冻结；正式实现继续保留现版照片生命周期、重试和本地原图安全边界。",
  recommendation: "已确认；仅在真实 bug、数据安全或可访问性问题出现时修改。"
});

Object.assign(r3ByID["public-profile-social"], {
  candidateTitle: "最终确认｜旧版布局基础",
  candidateVersion: "最终确认",
  summary: "关注数据、主要操作、内容分类、餐厅记录、动态、公开食单和安全操作已采用旧版基础并冻结；顶部身份区仍待明确。",
  recommendation: "下一版只处理顶部身份区；关注关系、动态/食单结构和安全操作继续冻结。"
});

Object.assign(r3ByID["lists-density"], {
  candidateTitle: "最终确认｜旧版布局基础",
  candidateVersion: "最终确认",
  summary: "八个区域全部保留旧版并冻结；现版食单模型、可见性、分享、同步和统一餐厅图片继续保留。",
  recommendation: "已确认；不再重做列表密度和成员管理层级。"
});

Object.assign(r3ByID["analytics-compositions"], {
  title: "数据分析 × 4｜重新设计候选版 V3",
  direction: "Needs redesign",
  directionLocked: true,
  candidateTitle: "重新设计候选版 V3｜真实 SwiftUI 信息图",
  candidateVersion: "重新设计候选版 V3",
  summary: "根据 Lafayette 高保真参考重新构图：中心 Food Hero、周边节点与连接线、TOP 3、数据总览、近期洞察、偏好/消费/人均/城市/饭搭子/用餐时间都在同一编辑式信息图中。四页使用不同真实语义，不是普通纵向卡片。",
  visuals: [
    ...r3ByID["analytics-compositions"].visuals,
    r3v("Lafayette 最终视觉参考", "我的口味档案｜高保真构图 Source of Truth", R4_REFERENCE + "lafayette-taste-profile-source-of-truth.png", "Lafayette 上传的高保真视觉参考；约束中心食物主视觉、节点关系、不对称平衡、留白、信息层级和图像与数据关系。")
  ],
  fuseVisuals: [
    r3v("重新设计 V3｜真实实现", "最佳饭搭子 V3", R4_CANDIDATE + "analytics-companion-v3.png", "共同到访、共同评分、回头率、双人人均、TOP 3 与近期洞察围绕真实双人餐桌 Food Hero。", R4_CLEAN + "analytics-companion-v3-clean.png"),
    r3v("重新设计 V3｜真实实现", "谁最会种草 V3", R4_CANDIDATE + "analytics-source-v3.png", "来源命中、推荐次数、新店、踩坑、TOP 3 与来源偏好保持独立语义，不用餐厅总评分冒充来源结论。", R4_CLEAN + "analytics-source-v3-clean.png"),
    r3v("重新设计 V3｜真实实现", "本月回顾 V3", R4_CANDIDATE + "analytics-monthly-v3.png", "月度到访、餐厅、新店、消费、时间主线、TOP 3 与近期洞察围绕本月核心 Food Hero。", R4_CLEAN + "analytics-monthly-v3-clean.png"),
    r3v("重新设计 V3｜真实实现", "年度回顾 V3", R4_CANDIDATE + "analytics-annual-v3.png", "全年到访、餐厅、城市、消费、回头率、TOP 3 与年度洞察组成全年味觉轨迹。", R4_CLEAN + "analytics-annual-v3-clean.png")
  ],
  proposedFinal: ["沿用已确认口味档案的标题、叙事、分享入口与大幅信息图骨架。", "中心 Food Hero + 四周数据节点 + 连接线；后续继续呈现核心洞察、TOP 3、分布、代表餐厅图文与品牌区。", "四页共享家族，但关系、来源、月度、年度的语义和视觉故事不同。"],
  recommendation: "这是全新 V3，不继承此前被否决候选的区域冻结；请逐页对照 Lafayette Reference，并按八个区域重新审批。"
});

Object.assign(r3ByID["poster-family"], {
  title: "五类分享海报｜重新设计候选版 V3",
  direction: "Needs redesign",
  directionLocked: true,
  candidateTitle: "重新设计候选版 V3｜真实 9:16 SwiftUI Renderer",
  candidateVersion: "重新设计候选版 V3",
  summary: "五张海报均为原生 9:16 SwiftUI renderer 输出，并分别采用口味轨道、共同餐桌、推荐来源小票、月度节奏和年度轨迹；不是同一模板换标题。",
  visuals: [
    ...r3ByID["poster-family"].visuals,
    r3v("Lafayette 最终视觉参考", "Analytics / Poster 高保真视觉家族", R4_REFERENCE + "lafayette-taste-profile-source-of-truth.png", "作为编辑式信息图、Food Hero、留白、节点关系与视觉传播价值的共同家族参考；五张海报仍按各自真实语义重新构图。")
  ],
  fuseVisuals: [
    r3v("重新设计 V3｜真实 9:16 SwiftUI", "我的口味档案海报 V3", R4_CANDIDATE + "poster-taste-v3.png", "中心食物轨道、偏好/人均/回头率/评分、代表餐厅真实图片与正式品牌底部。", R4_CLEAN + "poster-taste-v3-clean.png"),
    r3v("重新设计 V3｜真实 9:16 SwiftUI", "最佳饭搭子海报 V3", R4_CANDIDATE + "poster-companion-v3.png", "两盘真实食物、共同身份与 42 次到访构成双人餐桌故事。", R4_CLEAN + "poster-companion-v3-clean.png"),
    r3v("重新设计 V3｜真实 9:16 SwiftUI", "谁最会种草海报 V3", R4_CANDIDATE + "poster-source-v3.png", "推荐来源小票与核心 Food Hero 表达靠谱来源和踩坑，不伪造数据结论。", R4_CLEAN + "poster-source-v3-clean.png"),
    r3v("重新设计 V3｜真实 9:16 SwiftUI", "本月回顾海报 V3", R4_CANDIDATE + "poster-monthly-v3.png", "九月主线大图、周节奏、到访/餐厅/消费与代表餐厅证据。", R4_CLEAN + "poster-monthly-v3-clean.png"),
    r3v("重新设计 V3｜真实 9:16 SwiftUI", "年度回顾海报 V3", R4_CANDIDATE + "poster-annual-v3.png", "年度轨迹、四季节点、城市/到访/餐厅与代表餐厅证据。", R4_CLEAN + "poster-annual-v3-clean.png")
  ],
  proposedFinal: ["一句核心结论 → 中心 Food Hero 与数据节点 → 代表餐厅真实图片 → 关键词 → 品牌/隐私/QR 底部。", "五类共享传播识别，但每张只表达其真实主题数据。", "正式 ImageRenderer、分享/保存、临时文件和隐私合同在最终采用时继续保留。"],
  recommendation: "此前 A/B 不再作为推荐；请逐张审批新的 V3，并按区域反馈继续收敛。"
});

Object.assign(r3ByID["premium-paywall"], {
  title: "Premium 会员页｜汉堡恢复候选版 V3",
  candidateTitle: "会员页汉堡恢复 V3｜真实 SwiftUI 实现",
  candidateVersion: "重新设计候选版 V3",
  summary: "只替换 Lafayette 指定的 Paywall 汉堡主视觉：直接复用正式 PremiumBurgerBadge 的已认可历史资产，不另画平行汉堡。标题、权益、商品事实、购买、恢复、法律与免费/Premium 状态全部继续冻结。",
  fuseVisuals: [
    r3v("重新设计 V3｜真实实现", "Premium 已认可汉堡主视觉 V3", R4_CANDIDATE + "premium-paywall-v3.png", "候选分支真实 SwiftUI；复用正式 PremiumBurgerBadge，不改 StoreKit、商品事实或服务端会员权益。", R4_CLEAN + "premium-paywall-v3-clean.png")
  ],
  proposedFinal: ["仅替换 Paywall 汉堡主视觉区域。", "其余七个冻结区域保持第二轮 FUSE 构图与正式商业事实。"],
  recommendation: "本轮只审批汉堡区域；其余区域不允许随候选继续变化。"
});

Object.assign(r3ByID["settings-data"], {
  candidateTitle: "现版已确认｜已冻结",
  candidateVersion: "最终确认",
  summary: "十个区域全部保留现版并冻结；本轮没有 Settings 候选改动。",
  recommendation: "已确认；不增加无目的品牌装饰。"
});

function r3Frozen(choice, notes = "第二轮 Lafayette 已确认") {
  return { choice, frozen: true, notes };
}

function r3Pending(choice = "NEEDS REDESIGN", notes = "") {
  return { choice, frozen: false, notes };
}

function allRegions(decisionID, valueFactory) {
  return Object.fromEntries(r3ByID[decisionID].regions.map((region) => [region, valueFactory(region)]));
}

window.round3InitialState = {
  "my-map-list": {
    decision: "",
    notes: "此前 Codex Visual PASS / CLOSED 不构成 Lafayette 人工视觉批准；本页及全部区域重新开放审批。",
    regions: allRegions("my-map-list", () => r3Pending(""))
  },
  "discovery-core": {
    decision: "",
    notes: "发现页此前的自动验收不构成人工视觉批准；五个一级入口和内容卡片全部待 Lafayette 逐区决定。",
    regions: allRegions("discovery-core", () => r3Pending(""))
  },
  "add-restaurant-nearby": {
    decision: "",
    notes: "只重新开放视觉与布局审批；fresh GPS、provider identity、去重和数据语义不因视觉选择改变。",
    regions: allRegions("add-restaurant-nearby", () => r3Pending(""))
  },
  "restaurant-detail-global": {
    decision: "",
    notes: "只重新开放统一主体的视觉审批；全局唯一 Restaurant Detail 和跨入口一致性必须保留。",
    regions: allRegions("restaurant-detail-global", () => r3Pending(""))
  },
  "roulette-core": {
    decision: "",
    notes: "轮盘算法和候选身份语义保持不变；页面构图、轮盘几何和结果区域等待 Lafayette 人工审批。",
    regions: allRegions("roulette-core", () => r3Pending(""))
  },
  "profile-density": {
    decision: "FUSE",
    notes: "添加好友和设置保持旧版左上/右上；Profile Premium 标识继续使用旧版已确认汉堡。",
    regions: {
      Header: r3Frozen("KEEP LEGACY", "第一轮 Lafayette 已确认"),
      "Social Metrics": r3Frozen("KEEP FUSE", "总消费放在想去旁边；人物名字下面显示关注和粉丝。"),
      "Main Statistics": r3Frozen("KEEP LEGACY", "第二轮 Lafayette 已确认"),
      "Core Entries": r3Pending("NEEDS REDESIGN", "两边看起来不对称，不协调。"),
      "Memory / 回味": r3Frozen("KEEP FUSE"),
      Lists: r3Frozen("KEEP LEGACY"),
      Insights: r3Frozen("KEEP FUSE"),
      Settings: r3Frozen("KEEP LEGACY", "第一轮 Lafayette 已确认")
    }
  },
  "visit-editor-density": {
    decision: "FUSE",
    notes: "选择一目了然、直接点、直接保存；不再点击展开。视觉完全按旧版基础执行。",
    regions: {
      Header: r3Frozen("KEEP LEGACY"),
      "Restaurant Context": r3Frozen("KEEP LEGACY"),
      "Core Experience": r3Frozen("KEEP LEGACY"),
      Ratings: r3Frozen("KEEP LEGACY", "详细评分采用旧版文字说明；餐厅总评分位于最上方。"),
      "Dish / Photo Entry": r3Frozen("KEEP LEGACY"),
      "Dining Context": r3Frozen("KEEP LEGACY"),
      Notes: r3Frozen("KEEP LEGACY"),
      "Save CTA": r3Frozen("KEEP LEGACY")
    }
  },
  "dish-photo-composition": { decision: "Legacy", regions: allRegions("dish-photo-composition", () => r3Frozen("KEEP LEGACY")) },
  "public-profile-social": {
    decision: "Legacy",
    regions: {
      Header: r3Pending("", "顶部身份区仍待决定。"),
      "Social Metrics": r3Frozen("KEEP LEGACY", "被关注统一显示为粉丝。"),
      "Primary Actions": r3Frozen("KEEP LEGACY"),
      "Content Tabs": r3Frozen("KEEP LEGACY"),
      "Restaurant Evidence": r3Frozen("KEEP LEGACY", "用户头像居中，并与我的页面身份视觉保持一致。"),
      "Activity Feed": r3Frozen("KEEP LEGACY", "公开内容分类应显示动态和食单。"),
      "Public Lists": r3Frozen("KEEP LEGACY"),
      "Report / Block": r3Frozen("KEEP LEGACY")
    }
  },
  "lists-density": { decision: "Legacy", regions: allRegions("lists-density", () => r3Frozen("KEEP LEGACY")) },
  "analytics-compositions": {
    decision: "Needs redesign",
    notes: "我的口味档案最终整体接近 Lafayette 参考图：中央大型 Food Hero、四周菜系节点和连接线；左右分布 TOP3、数据总览和近期洞察；下方展示口味偏好、消费、人均、城市足迹、饭搭子和用餐时间。白色/微暖、现代、轻编辑设计感、留白充分；不得退化成普通纵向 Dashboard Card。具体内容必须由真实数据动态生成。",
    regions: allRegions("analytics-compositions", () => r3Pending())
  },
  "poster-family": {
    decision: "Needs redesign",
    notes: "第二轮 A/B 全部否决。海报继续遵守 Lafayette 口味档案参考图的信息图构图家族：中央 Food Hero、周边节点、连接线和不对称信息分布，但五类海报需按各自真实数据语义重新构图。",
    regions: allRegions("poster-family", () => r3Pending())
  },
  "premium-paywall": {
    decision: "Legacy",
    regions: {
      Header: r3Frozen("KEEP FUSE"),
      "Approved Hamburger": r3Pending("NEEDS REDESIGN", "只重做 Paywall 汉堡区域。"),
      "Benefit Hierarchy": r3Frozen("KEEP FUSE"),
      "Product Facts": r3Frozen("KEEP FUSE"),
      "Purchase CTA": r3Frozen("KEEP FUSE"),
      Restore: r3Frozen("KEEP FUSE"),
      Legal: r3Frozen("KEEP FUSE"),
      "Free / Premium States": r3Frozen("KEEP FUSE")
    }
  },
  "settings-data": {
    decision: "Current",
    notes: "第一轮 Lafayette 已确认。",
    regions: allRegions("settings-data", () => r3Frozen("KEEP CURRENT", "第一轮 Lafayette 已确认"))
  }
};

window.visualApprovalStorageKey = "tastemap.visualApproval.round3";
window.visualApprovalInitialState = window.round3InitialState;
window.visualApprovalSummaryTitle = "# Taste Map — Lafayette 完整核心页面人工视觉审批记录";
window.visualApprovalPreviousRoundLabel = "第二轮";
