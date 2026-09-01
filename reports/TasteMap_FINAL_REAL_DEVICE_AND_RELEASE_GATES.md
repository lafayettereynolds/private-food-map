# Taste Map｜最终真机与发布人工 Gate

日期：2026-09-01

适用代码：`fix/product-ux-correction-8-tasks` 上完成 Task 01–14 的最终候选版本

自动化结论：**READY FOR REAL-DEVICE RELEASE SMOKE**

边界：本文只列必须由 Lafayette、真实 iPhone 或外部平台完成的工作；Codex 能安全自动完成的项目不再转交给用户。

## 0. 当前不需要 Lafayette 做的事

- 不需要再用真实用户数据执行第二次 Legacy Import。F1-C4 精确重复导入、跨 provider 手动 Restaurant merge、Visit 重解析、`exactDuplicate`、无第二条 Visit、无额外 mutation 的自动化已经通过，原 blocker 已关闭。
- 不需要在 Simulator 使用真实 Sign in with Apple。DEBUG-only Visual QA 已提供隔离的 Logged In + Premium Active Rich Demo；Release binary 中不存在该入口。
- 不需要现在配置或访问 Production。
- 不需要重新创建 Xcode 项目、App ID、Bundle ID、Team 或 Capability。

## 1. 真实 iPhone Release Smoke

| 项目 | 内容 |
|---|---|
| 去哪里 | Mac 上连接 iPhone，在 Xcode 选择正式 `TasteMap` Target 和真实设备；必要时在 iPhone 解锁、信任、Face ID。 |
| 做什么 | 安装最新候选 build，验证首次启动、真实 Apple 登录、重启恢复、退出/再次登录；快速浏览 Map、Discovery、Profile、Settings。 |
| Codex 之后怎么验证 | 读取真机构建/安装/launch 结果，并根据用户确认记录 smoke 结论；不会把人工步骤伪报为自动化。 |
| 是否涉及 Secret | 否；Apple 账号凭据只由系统 UI 处理。 |
| 是否不可逆 | 否。 |
| 预计耗时 | 10–15 分钟。 |

## 2. GPS、Nearby、地图 Marker 与真实餐厅动作

| 项目 | 内容 |
|---|---|
| 去哪里 | 真实 iPhone 的 Taste Map 与系统“设置 → 隐私与安全性 → 定位服务”。 |
| 做什么 | 在精确定位开启与 Reduced Accuracy 两种状态下检查 fresh CLLocation、Nearby 距离排序、当前位置头像 Marker、拖动/缩放、重叠独立 Marker 的可点击性；再检查真实餐厅照片、电话、导航。 |
| Codex 之后怎么验证 | 对照 Sync/Location diagnostics 与用户看到的距离、排序和跳转；如有问题只修对应链路。 |
| 是否涉及 Secret | 否。 |
| 是否不可逆 | 否。 |
| 预计耗时 | 15–20 分钟。 |

## 3. Share Extension 与外部来源导入

| 项目 | 内容 |
|---|---|
| 去哪里 | 真实 iPhone 上的 Apple 地图、高德地图、Safari 和系统 Share Sheet。 |
| 做什么 | 分别分享 Apple Maps、AMap、普通 HTTPS URL、名称+地址、仅地址/坐标到 Taste Map；确认主 App 打开统一 Add Restaurant flow，且不会未经确认自动写 Restaurant。 |
| Codex 之后怎么验证 | 检查 App Group pending item、统一 parser 结果、幂等和消费时机；不记录分享内容中的 PII。 |
| 是否涉及 Secret | 否。 |
| 是否不可逆 | 否；测试记录可在 Development 本地删除。 |
| 预计耗时 | 10–15 分钟。 |

## 4. Development 真实内容、同味与 Community

| 项目 | 内容 |
|---|---|
| 去哪里 | 真实 iPhone 登录 Development Worker `api-dev.tastemap.cn` 的正式认证态。 |
| 做什么 | 检查真实用户的关注、为你推荐、同味之选、最新、趋势、Activity rating、Like/Comment、用户/餐厅跳转和用户隔离。 |
| Codex 之后怎么验证 | 只读 Development 日志与 D1 计数、对照自动化隔离测试；不访问 Production。 |
| 是否涉及 Secret | 用户不需要提供 Worker Secret。 |
| 是否不可逆 | 否；Like/Comment 属于 Development 可撤销操作。 |
| 预计耗时 | 10 分钟。 |

## 5. Roulette 触觉与 Reduce Motion

| 项目 | 内容 |
|---|---|
| 去哪里 | 真实 iPhone 的“今天吃什么”；再到系统辅助功能切换“减弱动态效果”。 |
| 做什么 | 检查 2/5/10 candidate、转盘旋转、结果卡、图片/名称/评分/城市、触觉反馈以及 Reduce Motion 降级体验。 |
| Codex 之后怎么验证 | 根据用户确认记录真机行为；自动化继续覆盖候选、筛选与结果逻辑。 |
| 是否涉及 Secret | 否。 |
| 是否不可逆 | 否。 |
| 预计耗时 | 5–8 分钟。 |

## 6. Analytics 海报保存、分享与 QR

| 项目 | 内容 |
|---|---|
| 去哪里 | 真实 iPhone 的“我的口味档案 / 最佳饭搭子 / 谁最会种草 / 本月回顾 / 年度回顾”。 |
| 做什么 | 打开五类 9:16 海报，检查代表餐厅真实图片优先、Food Hero、长文字、保存照片、微信/信息/AirDrop 分享；正式域名配置后扫描 QR。 |
| Codex 之后怎么验证 | 验证生成图片尺寸、Photos add-only 权限和最终公开 URL；正式 URL 缺失时 QR 应继续 fail closed。 |
| 是否涉及 Secret | 否。 |
| 是否不可逆 | 否。 |
| 预计耗时 | 10–15 分钟。 |

## 7. Sync Now 真机 Smoke

| 项目 | 内容 |
|---|---|
| 去哪里 | Taste Map → 设置 → Sync。 |
| 做什么 | 登录后点一次“立即同步/重试同步”，确认 push、pull、cursor、pending count、最后成功时间；切换 Wi-Fi/蜂窝仅作为最终 smoke，不再重复诊断性点击。 |
| Codex 之后怎么验证 | 对照 Development Worker 请求时序、D1 计数与客户端 diagnostics；不输出 token。 |
| 是否涉及 Secret | 否。 |
| 是否不可逆 | 否。 |
| 预计耗时 | 5 分钟。 |

## 8. Account Delete：仅一次性 Development 测试账号

| 项目 | 内容 |
|---|---|
| 去哪里 | Development 环境中专门创建的一次性账号；绝不能用 Lafayette 的主账号。 |
| 做什么 | 先 preview，再 confirm；验证 session revoke、Keychain/local current-user cleanup、D1 tombstone/anonymize、R2 retry、公开 share 失效和其他账号不受影响。 |
| Codex 之后怎么验证 | 只读核对 deletion job、Development D1/R2 计数和客户端状态。 |
| 是否涉及 Secret | 不向客户端提供 Secret；Cloudflare 只由受控服务端配置使用。 |
| 是否不可逆 | **是**，因此只允许一次性 Development 测试账号。 |
| 预计耗时 | 10–15 分钟。 |

## 9. Apple Developer 与 Distribution Signing

| 项目 | 内容 |
|---|---|
| 去哪里 | Apple Developer 与 Xcode Organizer。 |
| 做什么 | 确认 App ID `com.lafayette.tastemap`、Share Extension ID、App Group、Sign in with Apple、Associated Domains；为正式发布生成/选择 Distribution certificate/profile，再重新 Archive。 |
| Codex 之后怎么验证 | 对 Distribution Archive 执行 codesign/entitlement/binary/privacy manifest 扫描，并确认 `get-task-allow=false`。 |
| 是否涉及 Secret | Distribution certificate 私钥属于敏感材料，不应粘贴到聊天或 Git。 |
| 是否不可逆 | 否，但撤销证书会影响现有签名流程。 |
| 预计耗时 | 15–30 分钟。 |

## 10. App Store Connect / StoreKit

| 项目 | 内容 |
|---|---|
| 去哪里 | App Store Connect → Subscriptions / In-App Purchases；Apple App Store Server API 配置。 |
| 做什么 | 创建 Subscription Group、正式月/年 Product ID、价格、地区、本地化、审核材料；配置 Issuer ID、Key ID、`.p8` 与 App Store Server Notifications V2；完成 Sandbox 与 TestFlight purchase/restore/renewal/expiry/refund/revoke。 |
| Codex 之后怎么验证 | 通过正式配置注入检查产品加载、购买、restore、transaction updates、服务端 owner/idempotency；补 Apple `x5c` 独立验证 Gate。 |
| 是否涉及 Secret | **是**；`.p8`、Issuer/Key 配置只能进入受控 Secret store，绝不能进 iOS 或 Git。 |
| 是否不可逆 | Product ID/Subscription 结构一经创建通常不应随意改动，操作前需最终命名确认。 |
| 预计耗时 | 45–90 分钟，另加 Apple 处理时间。 |

## 11. Legal、Privacy 与 UGC 运营

| 项目 | 内容 |
|---|---|
| 去哪里 | 正式 HTTPS 站点、App Store Connect App Privacy、内部客服/审核流程。 |
| 做什么 | 发布并锁定 Privacy Policy、Terms、Support URL；依据 `docs/TASTEMAP_DATA_COLLECTION_MAP.md` 完成 App Privacy；指定 UGC moderation owner、SLA、申诉与支持渠道。 |
| Codex 之后怎么验证 | 运行 `ReleaseConfiguration` validation、链接可达性与 UI 条件显示检查；复核 Privacy manifest 与最终问卷一致。 |
| 是否涉及 Secret | 否。 |
| 是否不可逆 | 否，但法律文本变更需要版本管理和审核。 |
| 预计耗时 | 30–90 分钟，法律审核时间另计。 |

## 12. Production Cloudflare / D1 / R2

| 项目 | 内容 |
|---|---|
| 去哪里 | Cloudflare Dashboard / Wrangler 的 Production 环境。 |
| 做什么 | 在 Lafayette 明确授权后做 Production read-only preflight；确认 backups、migration ledger、D1/R2 bindings、Worker Secrets、rate limits，再逐个增量 migration/deploy。不得 reset/rebuild 数据库。 |
| Codex 之后怎么验证 | 每一步先后记录 preflight、migration、health check、rollback 边界和匿名/认证安全检查。 |
| 是否涉及 Secret | **是**；Cloudflare/R2/D1/Apple Secrets 仅进平台 Secret store。 |
| 是否不可逆 | Migration/deploy 可能影响真实数据，属于高风险 Gate。 |
| 预计耗时 | 30–60 分钟，视数据量与 migration 状态而定。 |

## 13. AASA 与 Associated Domains

| 项目 | 内容 |
|---|---|
| 去哪里 | 最终 Production 域名的 `/.well-known/apple-app-site-association` 与 Apple Developer/Xcode Associated Domains。 |
| 做什么 | 以 `docs/TASTEMAP_PRODUCTION_AASA_TEMPLATE.json` 为模板部署真实 AASA；配置正式 domain，验证无跳转、正确 MIME、Restaurant/Profile/List `/share/*` installed-app 与 web fallback。 |
| Codex 之后怎么验证 | 对域名做 HTTPS/AASA 内容检查，并在真实 iPhone 验证打开与 deleted/revoked/private link 行为。 |
| 是否涉及 Secret | 否。 |
| 是否不可逆 | 否。 |
| 预计耗时 | 15–30 分钟，加 CDN 缓存传播时间。 |

## 14. TestFlight

| 项目 | 内容 |
|---|---|
| 去哪里 | Xcode Organizer 与 App Store Connect TestFlight。 |
| 做什么 | 在 Distribution Archive、Production 配置、安全扫描和上面 Gate 完成后上传；执行真实 iPhone 安装、登录、同步、StoreKit、Share Extension、Analytics 海报、UGC 与删除预览 smoke。 |
| Codex 之后怎么验证 | 汇总 TestFlight build、crash/console、商店交易与 Worker metrics，形成 Go/No-Go。 |
| 是否涉及 Secret | 上传凭据由 Apple/Xcode 管理，不应写入 Git。 |
| 是否不可逆 | 上传本身可停止发布，不会自动上架。 |
| 预计耗时 | 30–60 分钟，加 Apple processing 时间。 |

## 15. App Store Submission

| 项目 | 内容 |
|---|---|
| 去哪里 | App Store Connect → App Review。 |
| 做什么 | 完成元数据、截图、隐私、年龄分级、订阅审核信息、审核账号/说明、出口合规，选择已通过 TestFlight 的 build 后提交。 |
| Codex 之后怎么验证 | 最终 release checklist、binary entitlements、legal URL、Production health、StoreKit 与真实设备 smoke 全部为绿后再允许提交。 |
| 是否涉及 Secret | 不应向审核说明暴露 Secret；仅提供必要测试账号。 |
| 是否不可逆 | 提交可撤回，但会进入外部审核流程。 |
| 预计耗时 | 30–60 分钟，加 App Review 时间。 |

## Gate 总结

- 当前工程自动化：P0 = 0，P1 = 0。
- 当前阶段允许：**安装真实 iPhone 并开始 Release Smoke**。
- 当前阶段不允许宣称：App Store Ready、Production Ready 或 StoreKit Live。
- Production、TestFlight、App Store 与真实订阅仍需按上述顺序完成并留存证据。
