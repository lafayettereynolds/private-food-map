# Taste Map Manual Release Configuration Checklist

本清单只记录必须由 Lafayette 在外部后台完成的发布配置。不要把 `.p8`、API Token、D1/R2 Secret、Apple 私钥或其他 Secret 粘贴到聊天、客户端代码、plist 或 Git。

## 1. Production Worker 与 API 域名

- Lafayette 去哪里操作：Cloudflare Dashboard → Workers & Pages → `private-food-map` → Settings / Domains & Routes。
- 填什么：为 Production Worker 绑定最终确认的 HTTPS API custom domain；随后把同一个 origin 写入 iOS Production API Base URL 的正式构建配置。不要使用 `api-dev.tastemap.cn`，也不要让 Production 缺失时回退到 Development。
- 完成后 Codex 如何验证：只读检查 Worker route、TLS 和 `/api/v1/*` fail-closed 行为；构建 Release App，确认其 Production Base URL 正确且产物不含 Development URL。

## 2. Production D1 migration

- Lafayette 去哪里操作：Cloudflare Dashboard → D1 → `food-map-db`，并在执行前明确授权 Codex 进行 Production 只读 preflight；实际 migration 另行明确授权。
- 填什么：先创建可恢复的数据库备份/导出并记录回滚负责人；确认 migration 从 Production 当前版本按文件名顺序增量执行，目标上限为 `0032_release_safety.sql`。禁止 reset、重建、清空或修改已经执行过的 migration。
- 完成后 Codex 如何验证：先只读列出表、行数基线与 pending migrations；授权后逐个应用缺失 migration，再只读复核 migration 状态、关键外键/索引和基线数据未丢失。

## 3. Production R2

- Lafayette 去哪里操作：Cloudflare Dashboard → R2 → Buckets，以及 Production Worker → Bindings。
- 填什么：确认正式 Bucket 是 `taste-map-photos`，并将 Worker binding 命名为 `PHOTO_STORAGE`；核对对象生命周期、CORS 和备份/恢复策略，不创建客户端 R2 Secret。
- 完成后 Codex 如何验证：只读检查 binding metadata；在获得单独 Production 写入授权后，用专用测试用户验证上传、读取、删除和账户删除对象清理，不读取其他用户对象。

## 4. Subscription Group 与正式 Product IDs

- Lafayette 去哪里操作：App Store Connect → My Apps → Taste Map → Monetization → Subscriptions。
- 填什么：创建或确认 Subscription Group；由 Lafayette 最终选择并记录月度、年度 Product ID，配置价格、销售地区、本地化、审核截图/说明和订阅条款。不要使用 Tests 中 `dev.*` fixture ID 作为正式 Product ID。
- 完成后 Codex 如何验证：只读核对 Product 状态；将确认后的 ID 通过 Worker Production configuration 注入 `APP_STORE_MONTHLY_PRODUCT_ID` / `APP_STORE_YEARLY_PRODUCT_ID`，再验证 iOS 展示只来自 StoreKit `Product`，无硬编码价格。

## 5. App Store Server API key

- Lafayette 去哪里操作：App Store Connect → Users and Access → Integrations → In-App Purchase。
- 填什么：创建具备最小必要权限的 In-App Purchase key，记录 Issuer ID 和 Key ID；将 `.p8` 只写入 Cloudflare Worker encrypted secret `APP_STORE_PRIVATE_KEY`，并把 Issuer/Key ID 作为受控配置注入。不要提交 `.p8` 或把其内容发送到聊天。
- 完成后 Codex 如何验证：只核对 secret 名称是否存在，不回显 Secret；用 Sandbox transaction 调用 server reconciliation，确认签名、Bundle ID、environment、product 和 `appAccountToken` 均通过验证。

## 6. App Store Server Notifications V2

- Lafayette 去哪里操作：App Store Connect → My Apps → Taste Map → App Information → App Store Server Notifications。
- 填什么：先设置 Sandbox URL，最后设置 Production URL，路径均为对应 Worker origin 的 `/api/v1/storekit/notifications`；选择 Version 2。
- 完成后 Codex 如何验证：触发 Apple 测试通知与 Sandbox 生命周期事件，确认 `notificationUUID` 幂等、未知 `appAccountToken` 不认领用户、最终 entitlement 与 Apple Server API 复核一致。

## 7. Sandbox / TestFlight StoreKit 验收

- Lafayette 去哪里操作：App Store Connect → Users and Access → Sandbox，以及 TestFlight → Internal Testing；测试时在真实 iPhone 的 App Store Sandbox/TestFlight 环境操作。
- 填什么：准备至少一个不含真实付费数据的 Sandbox tester；依次执行商品加载、购买成功、pending、取消、restore、续订、到期、billing retry、退款和撤销。
- 完成后 Codex 如何验证：观察 iOS 状态机、Worker transaction ledger 和 membership projection；确认跨用户交易认领被拒绝、重复通知/重试幂等、logout/用户切换不泄露 entitlement。

## 8. Privacy Policy、Terms 与 Support

- Lafayette 去哪里操作：最终选定的正式 HTTPS 网站/内容系统；完成后在 iOS Release configuration 中提供对应 URL。
- 填什么：发布可公开访问且内容真实的 Privacy Policy、Terms of Service、Support 页面；分别配置 `TASTEMAP_PRIVACY_POLICY_PROD_URL`、`TASTEMAP_TERMS_OF_SERVICE_PROD_URL`、`TASTEMAP_SUPPORT_PROD_URL`。不要填写占位域名或假页面。
- 完成后 Codex 如何验证：匿名 HTTPS 打开三个 URL，检查状态码、跳转和页面内容；运行 `ReleaseConfiguration` validation，并确认 Settings 只在 URL 合法时显示入口。

## 9. Production public origin、AASA 与 Associated Domains

- Lafayette 去哪里操作：Cloudflare Worker/custom domain、公开网页路由，以及 Apple Developer → Identifiers → `com.lafayette.tastemap`。
- 填什么：确认唯一 Production public HTTPS origin，注入 Worker `PUBLIC_SHARE_ORIGIN`；在该 origin 提供 `/.well-known/apple-app-site-association`，覆盖 Restaurant、Profile、List 公开分享路径；在 Taste Map Release entitlement 中添加精确的 `applinks:<production-domain>` 并刷新 Automatic Signing profile。不要把 Development applink 带进 Release。
- 完成后 Codex 如何验证：校验 AASA MIME/JSON、Team ID + Bundle ID、路径匹配和无重定向；真机验证 Restaurant/Profile/List universal link，并验证 revoked/private/deleted 内容返回不可用且不泄露数据。

## 10. UGC moderation 运营闭环

- Lafayette 去哪里操作：内部运营流程/工单系统及最终 Support 页面；App Store Connect Review Notes 中同步说明。
- 填什么：指定举报处理负责人、响应 SLA、内容政策、升级/封禁/申诉流程和用户联系渠道。现有代码已提供 report、block、删除自己的评论/内容；不要声称人工审核已运行，除非流程真实上线。
- 完成后 Codex 如何验证：用隔离测试用户提交举报、重复举报、屏蔽/取消屏蔽和删除自己的内容；确认 moderation 数据可被授权运营人员处理且 Feed/Search/Profile/Comment 均执行服务端隔离。

## 11. App Store Connect 发布资料

- Lafayette 去哪里操作：App Store Connect → My Apps → Taste Map → App Privacy / App Information / Prepare for Submission。
- 填什么：按最终 Production 数据流填写 Privacy Nutrition Labels、年龄分级、Support/Privacy URL、审核联系人、审核说明和可用的审核账号/登录步骤；解释 Apple 登录、UGC 举报屏蔽、账户删除和订阅恢复路径。
- 完成后 Codex 如何验证：对照 Release App 与清单逐项审计，不把 Privacy Manifest 当成 App Privacy 表单替代品；完成一次 TestFlight 安装与核心流程 smoke。

## 12. 最低系统真机 smoke

- Lafayette 去哪里操作：一台运行 iOS 17.x 的受支持 iPhone，或安装了 iOS 17 runtime 的 Xcode Simulator。
- 填什么：安装 Release 候选版本，验证启动、Apple 登录、地图/列表、餐厅与 Visit、照片、同步、Settings、分享和 Premium fail-closed；不修改 Production 数据。
- 完成后 Codex 如何验证：记录设备/系统/build 号和结果；重新运行 iOS 17 对应的 Debug/Release smoke，确认没有使用仅 iOS 18+ 的无保护 API。
