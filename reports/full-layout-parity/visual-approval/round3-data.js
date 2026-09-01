const R3_FORMAL = "round-3/formal/";
const R3_CANDIDATE = "round-3/candidates/";

function r3v(kind, title, src, caption) { return { kind, title, src, caption }; }

window.round3Decisions = structuredClone(window.round2Decisions || []);
const r3ByID = Object.fromEntries(window.round3Decisions.map((item) => [item.id, item]));

Object.assign(r3ByID["profile-density"], {
  title: "我的页面｜融合候选版 V3",
  candidateTitle: "融合候选版 V3｜真实实现",
  candidateVersion: "融合候选版 V3",
  summary: "关注/粉丝与去过/想去/总消费已经确认；核心入口因左右不对称、视觉不协调而等待下一版重新设计，其余已确认区域继续冻结。",
  fuseVisuals: [
    r3v("融合候选版｜真实实现", "我的页面融合候选版 V3", R3_CANDIDATE + "profile-fuse-v3.png", "独立候选分支真实 SwiftUI：添加好友/设置保持旧版位置；关注/粉丝在姓名下方；去过/想去/总消费同排。")
  ],
  proposedFinal: ["旧版紧凑身份骨架不变。", "姓名下方呈现关注与粉丝；主统计仅保留去过、想去、总消费。", "所有已冻结的核心入口、回味、食单、洞察与设置保持 V2 构图。"],
  recommendation: "第三轮已确认关注数据；下一版只允许修改核心入口的对称与协调关系，其他冻结区域不能重画。"
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
  title: "数据分析 × 4｜重新设计候选版 V2",
  direction: "Needs redesign",
  directionLocked: true,
  candidateTitle: "重新设计候选版 V2｜真实 SwiftUI 实现",
  candidateVersion: "重新设计候选版 V2",
  summary: "第二轮旧版方向候选被整体否决；本轮按已确认的“我的口味档案”信息图家族重新制作四张真实 SwiftUI 页面。",
  fuseVisuals: [
    r3v("重新设计 V2｜真实实现", "最佳饭搭子 V2", R3_CANDIDATE + "analytics-companion-redesign-v2.png", "共同到访、共同记忆、最常吃与最近一次围绕双人餐桌核心食物主视觉。"),
    r3v("重新设计 V2｜真实实现", "谁最会种草 V2", R3_CANDIDATE + "analytics-source-redesign-v2.png", "靠谱来源与最坑推荐来源使用各自真实语义，不用餐厅总评分冒充来源结论。"),
    r3v("重新设计 V2｜真实实现", "本月回顾 V2", R3_CANDIDATE + "analytics-monthly-redesign-v2.png", "月度次数、餐厅、新店和实际消费围绕当月核心食物主视觉。"),
    r3v("重新设计 V2｜真实实现", "年度回顾 V2", R3_CANDIDATE + "analytics-annual-redesign-v2.png", "全年到访、餐厅、消费和回头率形成年度味觉故事。")
  ],
  proposedFinal: ["沿用已确认口味档案的标题、叙事、分享入口与大幅信息图骨架。", "中心 Food Hero + 四周数据节点 + 连接线；后续继续呈现核心洞察、TOP 3、分布、代表餐厅图文与品牌区。", "四页共享家族，但关系、来源、月度、年度的语义和视觉故事不同。"],
  recommendation: "这是全新 V2，不继承第二轮任何区域冻结；请按八个区域重新审批。"
});

Object.assign(r3ByID["poster-family"], {
  title: "五类分享海报｜重新设计候选版 V2",
  direction: "Needs redesign",
  directionLocked: true,
  candidateTitle: "重新设计候选版 V2｜真实 9:16 SwiftUI 餐饮故事地图",
  candidateVersion: "重新设计候选版 V2",
  summary: "第二轮 A/B 全部否决；本轮只提供一套新的餐饮故事地图方向，仍是原生 9:16 renderer，不是页面截图或静态拼接。",
  fuseVisuals: [
    r3v("重新设计 V2｜真实 9:16 SwiftUI", "我的口味档案海报 V2", R3_CANDIDATE + "poster-taste-redesign-v2.png", "中心食物、三项核心数据、代表餐厅与正式品牌底部。"),
    r3v("重新设计 V2｜真实 9:16 SwiftUI", "最佳饭搭子海报 V2", R3_CANDIDATE + "poster-companion-redesign-v2.png", "共同用餐故事和代表餐厅证据。"),
    r3v("重新设计 V2｜真实 9:16 SwiftUI", "谁最会种草海报 V2", R3_CANDIDATE + "poster-source-redesign-v2.png", "可靠来源、记录次数与最坑推荐来源保持独立语义。"),
    r3v("重新设计 V2｜真实 9:16 SwiftUI", "本月回顾海报 V2", R3_CANDIDATE + "poster-monthly-redesign-v2.png", "当月次数、新店、实际消费和代表餐厅。"),
    r3v("重新设计 V2｜真实 9:16 SwiftUI", "年度回顾海报 V2", R3_CANDIDATE + "poster-annual-redesign-v2.png", "全年次数、餐厅、消费和年度代表餐厅。")
  ],
  proposedFinal: ["一句核心结论 → 中心 Food Hero 与数据节点 → 代表餐厅真实图片 → 关键词 → 品牌/隐私/QR 底部。", "五类共享传播识别，但每张只表达其真实主题数据。", "正式 ImageRenderer、分享/保存、临时文件和隐私合同在最终采用时继续保留。"],
  recommendation: "第二轮 A/B 不再作为推荐；请只审批新的 V2，并按区域反馈继续收敛。"
});

Object.assign(r3ByID["premium-paywall"], {
  title: "Premium 会员页｜汉堡重新设计候选版 V2",
  candidateTitle: "会员页汉堡重新设计 V2｜真实实现",
  candidateVersion: "重新设计候选版 V2",
  summary: "只重做 Lafayette 指定的 Paywall 汉堡主视觉；标题、权益、商品事实、购买、恢复、法律与免费/Premium 状态全部继续冻结。",
  fuseVisuals: [
    r3v("重新设计 V2｜真实实现", "Premium 汉堡主视觉 V2", R3_CANDIDATE + "premium-hamburger-redesign-v2.png", "候选分支真实 SwiftUI；不改我的页面已确认的小汉堡标识，也不触碰 StoreKit/服务端会员权益。")
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
window.visualApprovalSummaryTitle = "# Taste Map — Lafayette 第三轮视觉审批记录";
window.visualApprovalPreviousRoundLabel = "第二轮";
