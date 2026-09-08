# Taste Map Premium 产品与实现规则

更新时间：2026-09-07

## 开发者赠送 Premium（2026-09-07）

新增权威来源 `gift_annual`、`gift_lifetime`；App Store 月/年来源为
`app_store_monthly`、`app_store_annual`。原商品 ID、价格、订阅周期和权益不变。
`app_store_yearly` 只作为旧客户端缓存的兼容来源，迁移将已有数据库来源规范为 annual。
历史 `admin_grant` / promo / redeem_code / app_store_lifetime 继续读兼容，不能从新赠送入口创建。

Gift 绑定 Taste Map userID。gift_annual 从服务器发放时刻起一个 UTC 日历年，
闰日到下一年的 2 月末；gift_lifetime 的 expiresAt 必须为 null。
`startedAt` 对应现有持久化列 starts_at，同时保留 API startsAt 兼容字段。
延期从 max(当前时间, 原到期时间) 再加一年，保留原始 startedAt/grantedAt/grantedBy；
永久 Gift 无需延期。撤销不删除记录，保存 revokedAt 和执行管理员。

Premium access 是同一用户全部未撤销、已开始且未到期权益的并集。
显示来源优先级为 gift_lifetime > gift_annual > 有效 App Store/历史来源；
同级优先永久，再按最晚到期，最后以 ID 稳定排序。
Gift 到期/撤销后重新求值，仍有订阅则继续 Premium。StoreKit 只能更新
`app-store:<originalTransactionId>` 记录，不能覆盖 Gift。

App 仍通过 PremiumEntitlementService/TasteMapPlatform 判定；React 只渲染
服务层的 state、statusText、canManageSubscription，不能从用户资料 tier 自行提升会员。
账号更换清除状态并切换请求 generation，A→B→A 的旧请求也不能重新写回。
延续原有离线缓存最多 7 天；离线时无法实时得知服务端撤销，重新联网验证后以服务器为准。

Gift 用户的会员页显示：
- gift_annual：Taste Map Premium；赠送会员 · 有效期至 YYYY年MM月DD日。
- gift_lifetime：Taste Map Premium；永久会员 · 由 Taste Map 赠送。

日期展示使用 Asia/Shanghai。Gift 不显示管理订阅，App Store 订阅继续显示。
普通销售态只列 Monthly/Annual，隐藏 Gift 和 Admin；已批准设计、汉堡素材和权益清单不变。

内部页面是同源 `/internal/premium`，管理 API 是 `/api/v1/admin/memberships`。
每次请求验证真实 Taste Map Bearer 登录会话及服务端 MEMBERSHIP_ADMIN_USER_IDS
名单（兼容已有 ADMIN_EMAILS）；不接受本地测试身份或未经验证的 Access-email 请求头。
Token 只在页面内存中保存，退出/页面离开即清除。此页面和管理实现不打入 App React 资源。
发放/延长/备注/撤销的 entitlement mutation 与 audit INSERT 在 SQLite 同一事务完成；
审计保留 actor、target、action、before/after 及 userID/source/grantedAt/expiresAt/grantedBy/note/revokedAt。

部署/操作和本轮验证证据见 `docs/PREMIUM_GIFT_ADMIN.md`。

## 产品定位

Taste Map Premium 的核心价值是：把用户长期积累的餐厅与到访记录，转化为更完整、更可解释的个人分析和推荐能力。会员身份不影响公开评分权重、好友推荐排序或普通记录的所有权。

## 免费版与 Premium

免费版长期保留：

- 正常记录 Restaurant、Visit、评分、笔记和想吃；
- 基础个性化推荐、好友评分、重复到访与“那年今日”；
- 普通食单和全部预设头像；
- 每次到访照片上限为 2 张（含菜品照片；Premium 为 20 张）。

Premium 开放：

- 完整口味档案；
- 深度“为你推荐”理由与高级推荐筛选；
- 同味之选与同味评分；
- 饭搭子分析与推荐来源分析；
- 本月回顾、年度食味年鉴与更完整的消费洞察；
- 自定义头像；
- 每次到访最多上传 20 张新照片。

权限的代码真值来自统一 Feature Catalog / `canUseFeature` 与服务端 Entitlement。页面不得根据用户名、测试账号名或本地开关自行判断会员。

推荐来源分析中的“最坑”是该 Premium 分析的一部分，不另设独立付费项。免费用户仍可正常记录推荐来源；只有进入完整推荐来源分析后，才会在满足独立餐厅样本门槛时看到“最坑”结论、详情证据和对应分享海报。

## 统一入口

以下入口全部调用 `openPremiumPaywall(sourceFeatureKey)`，打开同一个 `PremiumPaywallHost`：

- 本人资料中的轻量“开通 Premium”（免费账号）或用户名旁可点击的 Burger 标识（已开通账号）；
- 设置中的“会员与订阅”；
- 完整口味档案、同味之选、同味评分；
- 饭搭子分析、推荐来源分析；
- 深度推荐与高级筛选；
- 自定义头像；
- 免费照片上限提示；免费账号尝试添加第 3 张到访照片时，“继续添加”直接进入该会员页。

`sourceFeatureKey` 只用于记录入口来源和显示对应说明，不改变最终权限。

## 会员页结构

项目只维护一个 Premium 页面，由服务端 Entitlement 自动切换两种状态，不建立第二套“会员中心”：

### 免费销售态

1. `Taste Map Premium` 与“把长期记录，变成更懂你的分析。”；
2. 六项核心权益；
3. 免费版与 Premium 对比；
4. StoreKit 月度、年度方案，年度方案作为推荐项；
5. 恢复购买、服务条款和隐私政策入口。

### 已开通状态态

1. `Taste Map Premium` 与“已开通”；
2. 当前方案、开通来源以及适用的续订日期或有效期；
3. 可展开的 Premium 权益；
4. 恢复购买；
5. 仅 App Store 月度/年度订阅显示“管理 App Store 订阅”。

来源分支必须保持明确：

- `app_store_monthly` / `app_store_yearly`：显示续订或有效期，并允许进入 App Store 订阅管理；
- `app_store_lifetime`：显示永久方案，不显示续订日期或订阅管理；
- `admin_grant` / `promo` / `redeem_code`：显示赠送、活动或兑换来源与相应有效期，不显示 App Store 订阅管理。

## 价格与购买

- 价格必须由原生 StoreKit 通过 Membership Store Bridge 返回本地化 `displayPrice`；前端不得硬编码金额或币种。
- 年度节省比例仅在月度、年度都提供同币种数值价格时计算。
- Web 环境显示“暂时无法获取订阅信息”与重试入口，并说明需在 iPhone App 中查看价格或恢复购买；不展示假价格。
- 购买和恢复成功后必须重新读取服务端 Entitlement；客户端回调本身不能直接授予会员。
- 页面监听统一会员状态变更事件，购买、恢复、后台授予、撤销或到期后的 Entitlement 刷新会立即切换 Profile 入口和会员页状态，不要求用户重新加载页面。
- 原生商品不可用、购买失败或恢复失败时，按钮恢复可操作并显示可重试错误。

当前桥接契约已在 Web 代码中就绪；实际 StoreKit 商品、App Store 沙盒/正式购买、收据校验和续期需要在 iOS 与服务端发布流程中完成。

## 数据保留与降级

- 会员到期、撤销或购买失败不得删除 Restaurant、Visit、想吃、食单、头像或照片。
- 免费用户不能继续超过免费上限新增照片；已有超过 2 张的历史照片继续可读，笔记、评分等无关编辑及重排/删除不得裁掉其余旧照片。不得通过菜品照片、复用其他到访的照片 ID 或并发新增绕过上限；备份导入保留历史，不迁移删图。
- 既有自定义头像在降级后保留数据，不允许因为权限刷新而被清空；再次编辑自定义头像仍需 Premium。
- 会员分析结果动态读取现有数据，不另存一份容易过期的会员统计快照。

## 事件与验证

会员页记录打开入口、方案选择、购买、恢复和管理订阅等事件。测试至少覆盖：

- 月度/年度本地化价格与年度节省计算；
- Web 不支持购买的明确降级；
- 所有受限入口进入同一会员页；
- 购买/恢复后会员状态刷新；
- App Store 月度/年度、永久、后台赠送、活动和兑换码的状态分支及订阅管理按钮可见性；
- 免费 2 张、Premium 20 张照片上限；
- 降级后历史数据和照片不丢失。


## Referral Premium Reward（2026-09-07）

新增 `referral_reward` fixed-term entitlement 和独立 Reward Balance，不新增或修改 Monthly / Annual StoreKit 商品。

- 服务端新账号注册时绑定唯一 referrer；第一条有效 Visit 同步成功后 qualified。
- 邀请人终身最多 5 个 qualified 名额，每人 30 天、最多 150 天；受邀人一次性 14 天。
- 普通 Gift / Reward 的有效覆盖区间顺延；原始 Gift 与 Apple 行保留独立审计事实。
- 有效 App Store entitlement 期间，新奖励暂存；结束后从记录的结束时刻生效，不展示为 Apple 续费。
- Lifetime-at-grant 不增加期限；邀请名额照常占用。已获天数展示名义邀请奖励，待生效天数不含 lifetime 跳过项。
- 当前展示来源 precedence：Gift lifetime > Gift annual > App Store > Reward/其他固定期限来源；访问权取所有有效来源并集。Gift/Reward 展示连续奖励覆盖的最终到期日，App Store 日期原样保留。
- 撤销保留邀请名额，撤销双方对应奖励，并将后续未消耗奖励前移以消除空档；已消耗时间不能追回。

细则、操作与验收见 `REFERRAL_PREMIUM_REWARD.md`。
