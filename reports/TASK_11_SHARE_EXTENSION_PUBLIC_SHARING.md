# Taste Map Task 11 — Share Extension + Public Sharing 验收

日期：2026-09-01  
分支：`fix/product-ux-correction-8-tasks`

## 结论

**AUTOMATION PASS / REAL DEVICE PENDING**

本轮没有部署或访问 Production。Share Extension 继续只把分享证据原子写入 App Group；主 App 打开统一的 Add Restaurant 流程并要求用户明确确认，不会自动创建 Restaurant。公开 Restaurant、Profile、List 继续使用 192-bit 随机 opaque share ID、服务端实时可见性检查和匿名 allowlist projection。

## 本轮硬化

- 同一 HTTPS URL 即使分享来源改变标题/说明文字，仍稳定去重为同一个 pending import。
- Apple Maps、AMap、普通 HTTPS 网页、名称 + 地址、仅地址和坐标证据继续共用 `ExternalRestaurantLinkParser`，没有在 Extension 内复制解析逻辑。
- 增加被显式 revoke 的公开链接立即返回不可用的回归。
- 增加匿名公开分享读取的速率限制回归；达到限额后，不利用 opaque ID 是否存在产生可枚举差异。
- 增加 Restaurant / Profile / List 三类公开合同和 Universal Link opaque HTTPS route 自动化。
- 增加不包含任何假 Production 域名的 AASA 模板：`docs/TASTEMAP_PRODUCTION_AASA_TEMPLATE.json`。
- 海报 QR 在正式 URL 缺失、Development URL、localhost 或 workers.dev 情况继续 fail closed；分享海报仍由统一 `SharePosterBrandFooter` 和原生独立图片导出流程生成。

## Extension 安全边界

- 无 access token / refresh token / Keychain 访问。
- 只持有 App Group entitlement。
- payload 上限 32 KiB；空输入、HTTP URL、路径注入和过期记录 fail closed。
- JSON 文件使用 `.atomic` 写入；opaque SHA-256 文件名；重复分享幂等。
- 主 App 只有在用户选择“想吃”或“记录到访”后才消费 pending item。

## Public Sharing 安全边界

- create 必须使用 Worker 已验证用户身份；客户端 entity/user 字段不决定 owner。
- anonymous read 只返回公开安全投影。
- private、deleted、revoked、owner/profile 不公开时立即 unavailable。
- internal Restaurant/Profile/List ID 不进入 URL 或公开 response。
- Visit 私人备注、Apple/AMap identity、user ID、record ID、auth 字段不会进入公开响应。
- Restaurant 公开图仅使用合法 HTTPS merchant image；没有可用图片时诚实 fallback。

## 自动化结果

- Public sharing incremental migration fixture：PASS。
- Worker public sharing integration：7/7 PASS。
- iOS `Task09PendingImportTests`、`Task09PublicSharingTests`、`Task11SharingHardeningTests`：11 个定向测试 PASS。
- TypeScript app + Worker typecheck：PASS。
- Vite production build：PASS（仅保留既有 chunk size warning）。
- iOS Debug Simulator build：PASS。
- iOS Release Simulator build：PASS。
- Release main App configured URL scan：PASS。
- Release Share Extension binary/string scan：PASS。
- Release entitlement scan：PASS；不包含 Development Associated Domain。

## Release scan 结果

Share Extension Release 产物未发现：

- Development API URL；
- `workers.dev` / localhost URL；
- test auth header；
- access / refresh token；
- Bearer/JWT credential marker；
- private-key marker；
- Visual QA / Rich Demo / fake entitlement marker。

## Production AASA 合同

模板只声明已确认的 App ID `7G5J9MJX88.com.lafayette.tastemap` 与 `/share/*` route，不内置或猜测 Production 域名。正式域名、HTTPS hosting、MIME、无跳转响应和 Release Associated Domains 仍是人工 Release Gate。

## 真机 Manual Gate

以下没有伪报自动通过：

1. Apple Maps 系统 Share Sheet → Extension → App Group → 主 App 确认。
2. AMap 系统分享 URL / 文字。
3. Safari 普通 URL、仅文字、地址和坐标。
4. Photos add-only 保存海报。
5. 微信、信息、AirDrop 分享。
6. 配置正式 Production 域名后，Restaurant / Profile / List Universal Link 的 installed-app 与网页 fallback。

