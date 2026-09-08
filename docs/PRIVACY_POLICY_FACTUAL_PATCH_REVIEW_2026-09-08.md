# Privacy Policy factual patch — review only, not published

## Website provenance

Cloudflare's account control plane confirms `tastemap.cn` belongs to Worker **fancy-fog-1341** (account `a49735de26852ab995cd98bbb28e8bb8`). Most recent deployment: 2026-08-25T03:32:48.163404Z, source `wrangler`. The Worker source download API returned HTTP 204; Pages project listing returned no projects. This is a separate website deployment from `private-food-map` / `private-food-map-development`.

No original website source or deployment directory was found in project worktrees, git history, Desktop/Downloads ZIP inventories, local filenames/Spotlight, Wrangler logs or the searched historical task records. The temporary HTTP copy is evidence, **not** an identified source repository. Therefore no website HTML source was modified, no website release bundle is claimed ready, and nothing was published.

The following text is a narrowly scoped review draft for the existing sections. Apply to the actual website source only after it is recovered. Keep other existing policy text and layout unchanged. The retention text describes the candidate implementation; it must not be published ahead of the matching Worker migration/activation.

## Section 2 — add purchase and entitlement processing

使用“通过 Apple 登录”时，我们处理 Apple 返回的账户标识及你授权提供的姓名、电子邮箱，并将其与 Taste Map 用户标识关联，用于登录、同步和账户安全。

使用 Premium 时，我们仅处理提供和验证会员权益所必需的交易与权益信息，包括 StoreKit 交易标识、原始交易标识、商品 ID、权益状态、有效期、撤销或退款状态以及交易环境。我们通过 Apple App Store Server API 验证交易，并接收 App Store Server Notifications 以更新权益。

Taste Map 不收集你的银行卡号或完整支付卡信息，付款由 Apple App Store 处理。赠送会员和邀请奖励不是支付卡信息；为分配权益、避免重复发放及处理奖励状态，我们保存必要的赠送权益、邀请关系、奖励状态与奖励记录。邀请功能关闭时，已有记录仍依照本政策处理。

## Section 5 — replace supplier placeholder only

我们实际使用以下系统服务和基础设施：

- Apple：提供“通过 Apple 登录”、StoreKit、App Store 交易验证及服务器通知。传输范围限于身份验证和购买权益处理所需的信息，不意味着 Apple 获取 Taste Map 的全部业务数据。
- Apple MapKit：提供地图、地点搜索和导航等能力；相关请求可能涉及你授权的位置、搜索区域或地点信息。Taste Map 会保存你记录的餐厅坐标和城市，不持续记录后台移动轨迹。
- Cloudflare Workers：处理账户认证、数据同步、内容访问控制和会员权益等请求；D1 保存相应结构化记录；R2 保存你选择上传的照片及缩略图。图片通过所有权和可见范围校验后提供访问。

上述服务按各自职责处理相应数据。本政策不表示 Cloudflare 将 Taste Map 用户数据用于广告。

## Sections 7–8 — replace deletion placeholder and align retention statements

你可以在“我的 → 设置 → 账户与安全 → 删除账户”发起删除，并按提示重新验证身份和确认。删除处理开始后，账户停用，已有会话失效，相关公开内容撤下。完成身份清理后，Apple 身份关联和邮箱会从账户记录中移除。

你的 R2 照片原图与缩略图按账户范围分批删除。只有待处理清单和重新查询的账户图片范围均为空时，照片清理才视为完成。失败或中断的任务保留可重试状态，不会以成功代替失败。

账户删除完成不代表所有系统中的数据在点击时立即永久消失。为保证多设备同步、重试和防止旧设备恢复已删除内容，普通删除记录的业务内容保留 30 天后进入清理；账户删除后的到访、餐厅、UGC 内容及私有头像也在 30 天后进入清理。图片对象必须先删除，随后才清除对应存储引用。批量清理失败时会继续重试。

精简的记录标识、关联标识、删除时间和同步版本会在账户存续期间保留，用于正确下发删除状态；这些仍是关联数据，不称为匿名数据。账户关闭满 365 天后，相关业务记录、同步历史、删除任务记录和账户记录进入最终物理清理。

已关闭账户的安全会话在撤销满 90 天后清理，举报记录在最后更新满 90 天后清理，推荐事件在记录或接收满 90 天后清理。为交易核对和争议处理，必要的 Apple 交易及所有权证明保留至账户关闭及相关交易结束／最后更新均已满 365 天，再清除。若邀请关系仍支撑另一位用户尚未结束的奖励，最低限度的权益来源关系会保留到该奖励结束后 365 天；另一位用户仍有效的长期权益不会因邀请人删除账户而消失。已删除的到访内容和照片不因该关系而继续保留。

这里的保留窗口是 Taste Map 的产品处理规则，不声称所有记录均存在同一法律强制保留期限。供应商备份保留配置尚未由本轮代码审计证明；发布前应核实实际配置，不能用上述主业务库规则承诺所有供应商备份在同一天消失。

## Review/activation boundary

App Privacy remains unchanged and awaits the user's published-config screenshot. Manifest, Info.plist, MapKit, camera/PhotosPicker and add-only permission wording are unchanged. No deployment, Production D1 access, offer consumption, Hybrid cutover or Final RC generation is part of this patch.
