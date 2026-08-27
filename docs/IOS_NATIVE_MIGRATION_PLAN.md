# Taste Map Web → 原生 iOS 迁移方案

更新时间：2026-08-27

## 1. 当前基线与本轮边界

- Web App 是现阶段功能、交互和产品逻辑的基准版本；迁移期间不删除、不降级现有 Web 功能。
- 原生工程位于 `ios/TasteMap/TasteMap.xcodeproj`，使用 Swift、SwiftUI、SwiftData 和 MapKit。
- `main` 当前基线为 `cdf2982`。原先只存在于 Mac 的 3 个 iOS commit 已安全推送到 `origin/main`，Web 历史没有被覆盖：
  - `2c5ec6f Add native TasteMap iOS project`
  - `a3cab62 Implement Taste Map iOS V1 local visit flow`
  - `cdf2982 Restore three-tab iOS navigation`
- 本文件只定义迁移顺序、共享数据架构、模型差异和第一阶段文件计划；本阶段不大规模修改 SwiftUI 页面。
- SwiftData 与 IndexedDB 都是 local-first 缓存。跨设备、跨客户端的业务真值逐步统一到 Worker API + D1。
- 所有数据库变更必须使用新的增量 migration；不得删除、清空、重命名现有 Production D1。
- 不在 iOS 客户端、Web 代码或 Git 中写入 Cloudflare Secret、R2 Secret、OAuth Client Secret、API Secret 或长期访问令牌。

## 2. 目标架构

```text
React/Web UI ── Web Repository ── IndexedDB ── Sync Queue ─┐
                                                          ├── Worker API ── D1
SwiftUI UI ─── iOS Repository ─── SwiftData ── Sync Queue ┘        │
                                                                   └── PhotoStorageProvider
                                                                        ├── Google Drive（当前 Web）
                                                                        ├── R2（未来）
                                                                        └── 其他 Provider
```

### 2.1 数据责任

| 层 | 职责 | 不能承担的职责 |
| --- | --- | --- |
| IndexedDB / SwiftData | 离线读取、即时本地写入、待同步操作、失败重试、本地图片缓存 | 不能分别成为 Web 和 iOS 两套永久真值 |
| Worker API | 身份验证、权限过滤、输入校验、幂等写入、增量读取、冲突规则、照片授权 | 不保存客户端 Secret，不把 D1 直接暴露给客户端 |
| D1 | 用户、餐厅、到访及关系数据的跨平台真值；照片元数据和存储引用 | 不保存图片二进制、客户端缓存或 base64 图片 |
| PhotoStorageProvider | 上传、加载、删除图片对象 | UI 不直接依赖 Google Drive、R2、OSS/COS 的具体 SDK |

### 2.2 local-first 写入流程

1. UI 只调用平台 Repository，不直接调用网络层。
2. Repository 在一个本地事务中保存实体和 `SyncOperation`，UI 随即刷新；离线时也成功。
3. Sync Coordinator 在登录、启动、回到前台、网络恢复和手动重试时发送到 Worker。
4. 每次操作携带稳定 `operationId`；Worker 幂等处理，重复请求不能生成第二条实体。
5. Worker 返回服务端时间与增量游标；客户端合并后才删除已确认的队列项。
6. 失败使用持久化重试次数、退避时间和错误信息，不能无限 Loading。
7. 删除先写 `deletedAt` 软删除并入队，服务端确认后再按保留策略清理本地对象。

### 2.3 API 演进策略

现有 Web 已使用 `GET/POST /api/sync`，Worker 已具备 D1 snapshot、`since` 增量读取和按 `updatedAt` 合并。迁移应复用它，不另建生产后端。

P0 采用兼容式演进：

- 保留 `/api/sync`，确保当前 Web 不受影响。
- 增加明确的协议版本。推荐新增 `/api/v1/sync`，同时让旧 `/api/sync` 继续使用兼容适配器；如果继续共用原路径，则请求和响应必须增加可选 `schemaVersion`，旧客户端缺省时仍能工作。
- 初始响应至少包含 `schemaVersion`、`serverTime`、`nextCursor`、各实体增量和已确认的 `operationId`。
- 写入从“客户端 snapshot”逐步收敛为显式 operations；过渡期 Worker 可把旧 snapshot 转为相同的内部 upsert 操作。
- 先保留现有 last-write-wins 行为，但统一为服务端可比较的更新时间；不得依赖两台设备未校准的本地时钟作为最终冲突真值。对关键字段冲突保留服务端版本或修订号，为后续精细合并留接口。
- 所有 DTO 使用 ISO 8601 UTC 时间、JSON `null` 表示缺省，金额使用十进制定点字符串或最小货币单位，避免 JavaScript `number` 与 Swift `Decimal` 往返精度损失。
- 为 Web 与 Swift 建立同一组 JSON fixture/contract tests，确保字段名、枚举、`null` 和软删除语义一致。

### 2.4 原生身份认证

当前生产 Worker 主要依赖 Cloudflare Access 注入的 `Cf-Access-*` 头；iOS 不能自己伪造这些头，也不能内置 Cloudflare Service Token。当前 Worker 在生产请求缺少 Access 头时回退为 `owner`，在开放原生 API 前必须收紧，不能把它作为 iOS 登录方案。

推荐流程：

1. iOS 使用 `ASWebAuthenticationSession` 打开服务端授权入口。
2. 用户在受信任网页完成 Cloudflare Access/OAuth 登录。
3. Worker 生成一次性、短时、仅可兑换一次的 authorization code，并通过注册的回调 URL 返回。
4. iOS 将 code 兑换为短时 access token；refresh credential 只放 Keychain。
5. Worker 校验 token、解析稳定 user ID，并对每个查询按 viewer 过滤。

P0 需要先确定生产 Worker 基础 URL、回调 URL 和 token 生命周期。URL 和协议配置可以进入构建配置；任何 Secret 只能留在 Worker 环境变量或服务端 Secret Store。引入回调前还要确认最终 Bundle Identifier；当前工程文件中是 `com.lafayette.TasteMap`，与产品约束中的 `com.lafayette.tastemap` 大小写不一致。本方案不自行修改 Bundle Identifier、Team 或 Signing，需在实施认证前单独确认现有 App ID 的准确大小写。

## 3. 跨平台身份与主键方案

### 3.1 Restaurant

- 业务主键是 Taste Map 自己的 Global Restaurant ID，而不是高德或 Apple Maps POI ID。
- D1 当前 `restaurants.amap_poi_id` 为必填；Web `Restaurant.amapPoiId` 也为必填。这不能直接接收只拥有 Apple Maps 标识的 iOS 餐厅。
- P0 增加 Provider 映射表，例如 `restaurant_place_identifiers`：

| 字段 | 说明 |
| --- | --- |
| `id` | 映射记录 ID |
| `restaurant_id` | Global Restaurant ID |
| `provider` | `amap`、`apple_maps`、`manual` 等 |
| `external_id` | Provider 原始标识 |
| `created_at` / `updated_at` | 审计时间 |

- 对 `(restaurant_id, provider, external_id)` 建唯一约束，并按实际去重规则增加用户/Provider 查询索引。
- 增量迁移把现有 `amap_poi_id` 写入 `provider = 'amap'` 的映射；旧字段先保留，旧 Web 客户端继续工作。
- Apple MapKit 没有可用稳定标识时，允许 `manual` 证据；用标准化名称、地址和坐标做候选提示，但必须让用户确认，不能静默把相邻门店合并。

### 3.2 本地 ID 与远程 ID

- D1 与 Web 使用 `String` ID；现有记录不保证全部是 UUID。
- iOS 当前 SwiftData 使用本地 `UUID`。为避免破坏已安装 App 的本地数据，保留本地 UUID，并新增唯一可空 `remoteID: String?`。
- iOS 新建实体时同时生成 `UUID` 本地 ID 和 UUID 字符串 `remoteID`；从云端首次拉取旧 Web 数据时生成本地 UUID，并保存对应的远程 String ID。
- iOS 关系继续使用本地 UUID；网络 DTO 通过映射层使用 `remoteID`。不能把 Web 的任意 String 强制解析成 Swift UUID。
- `User.id` 始终按服务端 String 处理，不使用 Swift UUID 替代。

### 3.3 删除、重复与完整性

- Restaurant 和 Visit 继续分开；同一家 Restaurant 可以拥有多条 Visit。
- 再次到访始终创建新 Visit，幂等性只防止同一次提交被网络重放，不合并不同的到访。
- `rating` 允许 `null`；未操作评分控件时 Web、SwiftData、DTO 和 D1 必须全程保持 `null`。
- 明显重复餐厅优先按 Global Restaurant ID 和 Provider 映射识别；名称/地址/坐标只生成候选，不自动覆盖。
- Visit 删除必须软删除，不能级联删除其他 Visit，也不能自动删除 Restaurant。
- 图片上传失败不能回滚 Visit；Photo 作为独立同步状态重试。

## 4. Domain Model 差异

### 4.1 Restaurant

| 分类 | Web / D1 当前字段 | iOS 当前字段 | 迁移处理 |
| --- | --- | --- | --- |
| 身份 | `id: String`、`userId`、必填 `amapPoiId` | `id: UUID`、可选 `appleMapItemIdentifier` | P0 增加 `remoteID`、`userID`、Provider 映射；不把 Provider ID 当主键 |
| 基本信息 | `name`、`address`、`city`、经纬度、`phone`、`openingHours` | 名称、地址、经纬度 | P0/P1 补齐无损 DTO 和缓存字段 |
| 用户状态 | `visited/wantToGo`、`preferenceLevel` | 没有；地图“想吃”分栏为空 | P1 迁为用户与餐厅关系；短期可兼容旧 `status`，最终避免把共享餐厅本体变成用户状态 |
| 评分与标签 | overall/food/environment/service/value、tags | 没有 | DTO P1 无损读取，P2 提供原生编辑和展示 |
| 价格与笔记 | `pricePerPerson`、`longTermNote` | 没有 | P1 保留数据，P2 完整 UI |
| Marker / 图片 | marker type、photo ID、merchant URL、emoji；base64 仅本地 | 没有 | P2 通过 Photo metadata + Provider；不上传 base64 到 D1 |
| 同步 | `createdAt`、`updatedAt`、`deletedAt`、测试标记 | created/updated、无软删除、实体仅有简化 syncStatus | P0 增加软删除、远程修订/同步元数据，测试数据不得进入 Production |

结论：iOS 当前 Restaurant 只能表达 MapKit 搜索得到的最小门店信息，不能无损缓存 Web Restaurant。P0 必须先完成 DTO 与身份层，P1/P2 再逐步开放编辑字段。

### 4.2 Visit

| 分类 | Web / D1 当前字段 | iOS 当前字段 | 迁移处理 |
| --- | --- | --- | --- |
| 身份与关系 | String ID、user ID、restaurant ID | UUID ID、UUID restaurantId | P0 增加远程 ID 映射，不破坏现有本地 UUID |
| 核心记录 | visitedAt、可空半星 rating、note | 已具备 | 保持 `nil/null`、0.5～5.0 和多次 Visit 规则；增加 contract tests |
| 消费 | totalPrice、myActualSpend、paymentMode、pricePerPerson | 只有 `myActualSpend: Decimal?` | API 金额使用精确表示；P1 无损缓存，P2 完整编辑 |
| 用餐信息 | diningMode、partySize、queueDuration、场景、时长、份量、噪音、交通 | 没有 | P1 DTO/缓存兼容，P2 UI |
| 体验 | value/environment/service 分项评分及标签、specialNotes | 没有 | P2 |
| 来源与关系 | 推荐来源、sharedMealId、companions、companionIds | 没有 | P1 无损读取，P3 社交与饭搭子 UI |
| 菜品 | dishes，含评分、价格、photoId；base64 仅本地 | 没有 | P2 独立 Dish model + Photo 引用 |
| 图片 | photos 本地源、photoIds 云端引用 | 没有 | P2 独立 Photo model；保存 Visit 不等待上传 |
| 同步/删除 | created/updated/deleted、测试标记 | created/updated、syncStatus；删除为本地硬删除 | P0 改为软删除 + 持久化操作队列 |

“P1 完整 Visit”表示 iOS 必须能无损接收、缓存、再发送已有 Web Visit，即使高级字段到 P2 才开放编辑。否则 iOS 修改一个基础字段时可能把 Web 的菜品、标签或用餐信息覆盖掉。

### 4.3 User

| Web / D1 当前能力 | iOS 当前状态 | 迁移处理 |
| --- | --- | --- |
| UserProfile：String ID、昵称、邮箱、简介、城市、头像、预设头像、地图可见性、认证主体、时间与软删除 | 没有 User model；“我的”只统计本地 Restaurant/Visit | P0 建立只读的 CurrentUser/Session DTO 与最小缓存；P3 再迁资料编辑和公开主页 |
| 服务端 MembershipEntitlement 是会员真值 | 没有会员能力 | P4 实现；客户端字段不能授予会员，不在本轮接 StoreKit |
| Friendship、Follow、DiningCompanion、SharedMeal 等关系 | 没有 | P3；必须复用 Worker 权限过滤，不直接读取他人私有 Visit |

## 5. 完整功能迁移清单

状态定义：`已实现` 表示原生能力达到 Web 对应闭环；`部分` 表示只有最小本地版本；`未实现` 表示 Web 有而 SwiftUI 没有等价实现。

| 功能 | Web 对应代码 | Web 数据模型 | iOS 当前状态 | 已实现？ | Worker / D1 | Photo Provider | 优先级 | 前置依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 登录、用户身份与会话 | `worker/index.ts`、`src/services/cloudSync.ts`、`src/services/membershipService.ts` | UserProfile、MembershipEntitlement | 无登录、无服务端用户 | 未实现 | 必需 | 否 | P0 | 原生认证协议、API Base URL、Keychain |
| local-first 同步、队列与冲突 | `src/services/cloudSync.ts`、`src/services/cloudSyncData.ts`、`src/services/syncQueue.ts`、`src/db/appDb.ts` | CloudSnapshot、SyncQueueItem、SyncMetadata | 只有实体 `syncStatus`，没有 API/队列/游标 | 未实现 | 必需 | 元数据随后接入 | P0 | 协议版本、DTO、软删除、身份 |
| Global Restaurant Identity / 地图 Provider | `src/services/restaurantIdentity.ts`、`src/services/mapService.ts`、`src/services/maps/*`、`worker/index.ts` | Restaurant、ProviderPlace | MapKit 搜索 + Apple ID 可选；无 Global ID | 部分 | 必需 | 否 | P0 | Provider 映射 migration、ID 映射层 |
| 旧 Web 数据首次迁移与防误覆盖 | `src/services/cloudSync.ts`、`src/db/backup.ts` | CloudSnapshot、SyncCounts | 无云端计数、无迁移确认 | 未实现 | 必需 | 视照片而定 | P0 | 认证、同步、数据盘点 |
| 去过：地图/列表/足迹 | `src/App.tsx`、`src/components/MapView.tsx`、`src/components/RestaurantList.tsx`、`src/components/TasteFootprints.tsx` | Restaurant、Visit、RestaurantSummary | 地图 Marker 与基础空状态；无完整列表/足迹 | 部分 | 必需 | 可选 | P1 | P0 同步、完整 DTO |
| 想吃 | `src/App.tsx`、`src/components/AddRestaurantModal.tsx`、`src/db/social.ts` | WantToGo、Restaurant；旧 Restaurant.status 兼容 | 顶部分栏存在但没有数据与操作 | 未实现 | 必需 | 可选 | P1 | P0 身份、关系 API/模型 |
| 搜索真实餐厅 | `src/services/restaurantSearch.ts`、`src/services/amap.ts`、`src/components/AddRestaurantModal.tsx` | ProviderPlace、Restaurant | 已有 MKLocalSearch、错误和重试 | 部分 | 去重/跨端身份需要 | 否 | P1 | Global ID、Provider 映射 |
| 添加餐厅 / 选择去过或想吃 | `src/components/AddRestaurantModal.tsx`、`src/components/RestaurantRecordSummary.tsx`、`src/db/restaurants.ts` | Restaurant、Visit、WantToGo | 选择搜索结果后直接新增 Visit；无想吃、完整商家摘要 | 部分 | 必需 | 可选 | 搜索、身份、P0 同步 |
| 餐厅详情 | `src/components/RestaurantPreviewCard.tsx`、`src/components/RestaurantRecordSummary.tsx`、`src/components/RestaurantSocialStatsPanel.tsx` | RestaurantSummary、Visit、Photo、社交统计 | 基本信息、我的统计、Visit 历史 | 部分 | 个人数据必需；公共评分后续 | P2 后使用 | P1 | 完整 DTO、Repository |
| 新增/再次到访 | `src/components/AddVisitModal.tsx`、`src/components/VisitExtraFields.tsx`、`src/db/restaurants.ts` | Visit、VisitDish、Photo | 日期、可空评分、备注、个人消费；可重复 Visit | 部分 | 必需 | P2 后使用；保存不依赖上传 | P1 | P0 同步、完整 Visit 缓存 |
| Visit 历史、编辑和删除 | `src/components/AddVisitModal.tsx`、`src/components/ConfirmDeleteModal.tsx`、`src/components/RestaurantPreviewCard.tsx` | Visit | 可编辑/删除单条；当前本地硬删除 | 部分 | 必需 | P2 后使用 | P1 | 软删除、操作队列、冲突测试 |
| 餐厅图片、到访实拍、缩略图 | `src/components/VisitPhotoPicker.tsx`、`src/components/SyncedImage.tsx`、`src/services/photoSync.ts`、`src/services/photoStorage/*` | Photo、PhotoCacheEntry、photoIds | 只有空 PhotoStorageProvider 协议 | 未实现 | 元数据必需 | 必需 | P2 | P0 同步、Provider 选择、授权上传 |
| 菜品记录 | `src/components/DishEditor.tsx`、`src/components/VisitExtraFields.tsx` | VisitDish、Photo | 无 | 未实现 | 必需 | 菜品图需要 | P2 | 完整 Visit、Photo Provider |
| 多维评分、标签与长期偏好 | `src/components/VisitExtraFields.tsx`、`src/components/StarRating.tsx`、`src/components/RestaurantEditorModal.tsx` | Visit 分项评分/标签、Restaurant preference | 只有总评分 | 未实现 | 必需 | 否 | P2 | P1 Visit、共享枚举/校验 |
| 用餐人数、排队、场景、方式、消费拆分 | `src/components/VisitExtraFields.tsx`、`src/components/QueueDurationPicker.tsx`、`src/components/CompanionPicker.tsx` | Visit 全量字段 | 只有个人消费 | 未实现 | 必需 | 否 | P2 | 完整 Visit、金额契约 |
| 餐厅电话、营业时间、Marker 样式、长期笔记 | `src/components/RestaurantRecordSummary.tsx`、`src/components/MarkerStyleField.tsx`、`src/components/RestaurantEditorModal.tsx` | Restaurant | 无 | 未实现 | 必需 | Marker 图片需要 | P2 | Restaurant DTO、Photo Provider |
| 发现：关注/为你/同味/最新/趋势 | `src/components/CommunityPage.tsx`、`src/services/recommendationService.ts`、`src/services/socialApi.ts`、Worker `/api/community` | User、Visit、Restaurant、Follow、RecommendationEvent | 只有占位页面 | 未实现 | 必需 | 卡片图片需要 | P3 | P0 身份、P1 数据、P2 照片 |
| 好友、关注、公开用户主页/地图 | `src/components/FriendsPage.tsx`、`src/components/ProfilePage.tsx`、`src/services/publicProfile.ts`、`src/services/socialApi.ts` | Friendship、Follow、UserProfile、Visibility | 无 | 未实现 | 必需，且必须服务端权限过滤 | 头像需要 | P3 | 身份、隐私契约、照片 |
| 饭搭子与共享用餐 | `src/components/CompanionPicker.tsx`、`src/components/CompanionLinkManager.tsx`、`src/services/companionInsights.ts` | DiningCompanion、CompanionLinkRequest、SharedMeal | 无 | 未实现 | 绑定用户/共享餐必需 | 私人头像可选 | P3 | 完整 Visit、用户关系权限 |
| 社区互动与公开餐厅分享 | `src/components/CommunityPage.tsx`、`src/components/RestaurantQuickActions.tsx`、`src/components/RestaurantShareSheet.tsx` | Restaurant、RecommendationEvent；部分点赞/评论仅 Web 本地 | 无 | 未实现 | 需要先补统一社交 API，不能伪装已同步 | 图片可选 | P3 | 社交 API、公共 ID、深链 |
| 个人主页与资料/隐私 | `src/components/ProfilePage.tsx`、`src/components/UserAvatar.tsx`、`src/db/social.ts` | UserProfile、Visibility | 只有本地统计 | 未实现 | 必需 | 自定义头像需要 | P3 | 身份、User DTO、照片 |
| 统计、口味档案、月报/年报、分享海报 | `src/components/ProfileAnalyticsPanels.tsx`、`src/services/profileInsights.ts`、`src/services/tasteProfileCore.ts`、`src/services/analysisShare.ts` | Restaurant/Visit 派生数据，不新增快照 | 无 | 未实现 | 同步数据必需；算法可本地复用契约 | 海报/代表图需要 | P4 | P1/P2 完整数据、共享算法 fixture |
| 食单 | `src/components/RestaurantListsPanel.tsx`、`src/db/restaurantLists.ts`、Worker 食单 API | RestaurantListCollection、RestaurantListItem | 无 | 未实现 | 必需 | 封面可选 | P4 | 身份、Restaurant Global ID |
| 今天吃什么/抽签 | `src/components/RestaurantRoulette.tsx`、`src/App.tsx` | 当前会话候选，不持久化 | 无 | 未实现 | 候选餐厅来源需要，轮盘状态不需要 | 可选 | P4 | P1 Restaurant、产品 UI 迁移 |
| 外部链接识别与 Share Extension | `src/services/externalRestaurantLink.ts`、Worker `/api/external-place/resolve`、`ios/ShareExtension/*` 辅助源码 | Global Restaurant Identity 候选 | 辅助 Swift 未加入当前原生 Target/Capability | 未实现 | 必需 | 否 | 用户明确授权 App Group/Capability 后才实施 |
| Premium / StoreKit | `src/components/PremiumPaywall.tsx`、`src/services/membershipStore.ts`、Worker Entitlement API | MembershipEntitlement、审计记录 | 无 | 未实现 | 必需，Entitlement 为真值 | 影响照片额度 | P4 | P0 身份、服务端收据链路、用户单独授权 Capability/商品配置 |

## 6. 分阶段实施计划

### P0：数据模型与 Worker API

目标：在不改变主要 UI 的前提下，让 iOS 能安全登录、无损保存 Web domain、离线入队、与同一 D1 双向同步。

1. **锁定契约基线**
   - 为现有 `/api/sync`、Restaurant、Visit、User、Photo 建真实 JSON fixture。
   - 明确缺省值、枚举、时间、金额、`null`、软删除和测试数据隔离规则。
2. **Provider-neutral 餐厅身份**
   - 新增 D1 增量 migration 和 Worker 映射读写。
   - 保留旧 `amapPoiId` 兼容；为 Apple Maps/手工录入提供映射。
3. **原生认证**
   - 新增一次性 code 兑换与短时 token；iOS Keychain 保存凭据。
   - 收紧生产环境无身份请求回退为 `owner` 的行为；上线前先做 Web 回归。
4. **协议版本与幂等 operations**
   - 保留旧 Web endpoint；增加版本、游标、operation acknowledgment。
   - Worker 对每个 viewer 隔离数据并验证所有外键归属。
5. **iOS 缓存与 Repository**
   - 扩充 SwiftData 模型，加入 remote ID、软删除、同步操作和元数据。
   - UI 继续走 local-first；Repository 将现有 `LocalTasteMapStore` 行为纳入事务。
6. **首次同步与数据保护**
   - 登录后先读云端计数和 server state；云端为空但本地有数据时必须显式确认上传。
   - iOS 本地为空时只拉取，不能把空 snapshot 推到 D1。
   - 保留现有 iOS 本地 Restaurant/Visit，增量补 remote ID，不清库。

### P1：核心记录闭环

- 去过地图 + 列表 + 味觉足迹。
- 想吃关系、地图分栏和添加/移除。
- MapKit 搜索结果接入 Global Restaurant Identity 去重。
- 统一餐厅摘要，选择“去过”或“想吃”。
- 餐厅详情、完整 Visit 传输/缓存、基本字段编辑、多次到访、跨端软删除。
- P1 不要求把 P2 高级字段全部展示，但任何同步或基础编辑都不能丢掉它们。

### P2：完整记录和媒体

- PhotoStorageProvider 的授权上传、缩略图、缓存、删除和失败重试。
- 到访照片、餐厅 Marker 照片、菜品和菜品照片。
- 多维评分、体验标签、用餐方式、人数、排队、场景、支付/消费、饭搭子基础选择。
- 餐厅电话、营业时间、长期笔记、偏好和 Marker 样式。

### P3：发现与社交

- 发现五栏、推荐解释、关注/好友、用户搜索、公开主页与地图权限。
- 饭搭子关联、共享用餐和社区内容。
- 点赞/评论在统一社交 API 完成前必须明确是本地状态或保持未开放，不能伪装跨端同步。

### P4：分析、工具与商业化

- 统计、完整口味档案、月报/年报、那年今日、分析海报和系统分享。
- 食单、今天吃什么/抽签、外部分享导入。
- Premium、StoreKit、收据验证和服务端 Entitlement；不在 P0–P3 提前实现购买 UI。

## 7. P0 第一批文件级修改计划

以下是开始实现 P0 时预计修改/新增的文件，不表示本轮已修改这些源码。

### 7.1 复用并增量修改 Web / Worker

| 文件 | 计划 |
| --- | --- |
| `src/types/domain.ts` | 增加 Provider-neutral identity 的兼容类型；避免直接删除 `amapPoiId` |
| `src/types/cloudSync.ts` | 增加协议版本、游标、operation acknowledgment 和兼容字段 |
| `src/types/sync.ts` | 扩展所有 P0 实体的 operation 类型、服务端确认和重试状态 |
| `src/services/cloudSync.ts` | 保持当前 Web 行为，逐步发送版本化 operations；继续保留首次上传保护 |
| `src/services/cloudSyncData.ts` | 集中 DTO 适配和新旧字段默认值，避免 React 组件处理协议差异 |
| `src/services/restaurantIdentity.ts` | 接入 Global ID / Provider 映射，不让业务依赖高德唯一键 |
| `worker/index.ts` | 新增版本化 sync、原生 session/token、Provider 映射和更严格 viewer 校验 |
| `migrations/0015_restaurant_place_identifiers.sql` | 仅新增表/索引和迁移现有高德映射；不清空现有数据 |
| `src/services/*.test.ts` / Worker tests | JSON contract、幂等、权限隔离、软删除、兼容旧 Web 请求 |

P0 不需要修改 `App.tsx`、`MapView.tsx`、`CommunityPage.tsx` 等大规模 UI 文件，除非为同步失败/迁移确认增加最小状态入口。

### 7.2 增量修改当前 iOS 工程

| 文件 | 计划 |
| --- | --- |
| `ios/TasteMap/TasteMap/Models/Restaurant.swift` | 增加 remote ID、owner、city、状态/软删除及无损缓存字段；保留现有 UUID |
| `ios/TasteMap/TasteMap/Models/Visit.swift` | 增加 remote ID、owner、软删除及完整 Web Visit 字段；保持 rating 可空 |
| `ios/TasteMap/TasteMap/Models/SyncStatus.swift` | 与统一队列状态对齐，不把单个实体状态当完整队列 |
| `ios/TasteMap/TasteMap/Persistence/TasteMapPersistence.swift` | 注册新增 SwiftData models 和增量 SchemaMigrationPlan |
| `ios/TasteMap/TasteMap/Persistence/LocalTasteMapStore.swift` | 迁为 Repository 的本地事务实现；删除改软删除并入队 |
| `ios/TasteMap/TasteMap/TasteMapApp.swift` | 注入 AppEnvironment、Session、Repository、Sync Coordinator；不改 Team/Signing |

### 7.3 预计新增 iOS 文件

```text
ios/TasteMap/TasteMap/
├── Configuration/
│   └── AppEnvironment.swift
├── Models/Remote/
│   ├── SyncDTO.swift
│   ├── RestaurantDTO.swift
│   ├── VisitDTO.swift
│   └── UserDTO.swift
├── Persistence/
│   ├── SyncOperation.swift
│   ├── SyncMetadata.swift
│   ├── TasteMapSchemaMigrationPlan.swift
│   └── TasteMapRepository.swift
├── Services/API/
│   ├── TasteMapAPIClient.swift
│   └── APIError.swift
├── Services/Auth/
│   ├── AuthenticationClient.swift
│   ├── AuthenticationSession.swift
│   └── KeychainCredentialStore.swift
└── Services/Sync/
    └── SyncCoordinator.swift
```

测试文件：

```text
ios/TasteMap/TasteMapTests/
├── SyncDTOContractTests.swift
├── TasteMapRepositoryTests.swift
├── SyncCoordinatorTests.swift
└── TasteMapMigrationTests.swift
```

只有在构建配置确实需要 API Base URL 时才修改 `project.pbxproj`，并且只增加非敏感配置引用；不得改 `DEVELOPMENT_TEAM`、Signing、Bundle Identifier 或 Capability。更适合的做法是使用已纳入 Git、仅含非敏感 URL/环境名的 xcconfig，并让本机 Secret 永远不进入客户端构建。

## 8. 数据迁移与恢复策略

### 8.1 先判断 Windows/Web 数据在哪里

1. 登录相同生产身份，调用只读同步接口，记录 D1 中 Restaurant、Visit、Photo 和 User 的数量与更新时间。
2. 如果 D1 已有完整数据，iOS 第一次登录只执行 pull + 本地合并。
3. 如果 D1 为空而 Windows 浏览器 IndexedDB 有数据，先从 Web 现有备份/同步流程显式上传；不要让 iOS 生成空数据替代它。
4. `localStorage`、IndexedDB、浏览器缓存和没有加入 Git 的备份都不会随 GitHub 自动迁移。需要使用现有 `src/db/backup.ts` 的受控导出/导入或 Web 的首次上传流程。
5. Google Drive 中的图片二进制不迁入 Git/D1；D1 Photo metadata 必须仍能映射真实 storage key。P2 切换 R2 时做 Provider 级迁移，不改 Restaurant/Visit 主键。

### 8.2 防止数据丢失

- 首次同步前后都记录实体计数；减少数量必须能由软删除解释。
- 未识别的新枚举或字段不得被 iOS 解码后丢弃并用旧 DTO 覆盖云端。协议版本不支持时应停止写入并提示升级。
- iOS 基础编辑只 patch 已修改字段，或携带服务端 revision；在完整 DTO 无损能力完成前不能把简化对象作为全量 snapshot 上传。
- 照片失败、无定位权限、搜索失败和网络离线都不能阻止本地 Visit 保存。

## 9. P0 验收门槛

P0 完成后必须同时通过：

1. Web build/tests 通过，现有页面和 `/api/sync` 旧客户端兼容。
2. iOS Simulator build/tests 通过；Team、Signing、Capability 未变化。
3. TypeScript 与 Swift 使用相同 JSON fixture 往返，Restaurant/Visit/User/Photo 字段、`null` 和枚举不丢失。
4. 空 iOS 安装登录后能从 D1 拉取 Web 的真实 Restaurant 与 Visit。
5. iOS 离线新增未评分 Visit 立即出现；`rating == nil`，重启后仍在，联网后同步到 D1，Web 能看到同一条 Visit。
6. 同店第二次到访生成第二条 Visit；网络重试同一 `operationId` 不生成第三条重复记录。
7. Web 与 iOS 分别编辑不同 Visit 互不影响；删除一条 Visit 不删除其他 Visit。
8. 软删除能跨端传播；旧 Web 高德餐厅和新 iOS Apple Maps 餐厅都能通过 Provider 映射读取。
9. token 过期、401/403、超时和离线都有可重试状态，不白屏、不无限 Loading。
10. 不同用户不能读取/修改对方 private Visit；生产无认证请求不能回退为 owner。
11. D1 migration 只增量执行一次，并在 Development 验证后才进入 Production。
12. Secret 扫描通过；iOS 包、Git diff 和日志不包含 Secret 或长期 token。

## 10. 开始 P0 前需要确认的最少事项

这些事项会改变接口或 Apple 侧配置，不能由代码自行猜测：

1. **最终 Bundle Identifier 的准确大小写**：工程当前是 `com.lafayette.TasteMap`，先前产品约束写的是 `com.lafayette.tastemap`。认证回调和 Keychain Access Group 会受它影响；确认前不修改。
2. **生产 Worker 基础 URL**：URL 本身不是 Secret，可作为环境配置；不要提供 Cloudflare Secret。
3. **原生登录方案**：推荐 `ASWebAuthenticationSession + 一次性 code + 短时 token`。若 Cloudflare 已有适合原生的认证网关，应先复用现有能力。
4. **P2 图片 Provider 方向**：Web 当前默认 Google Drive；已有 R2 bucket 不等于已完成客户端授权上传。P0 保持 Provider 抽象，P2 再决定继续 Drive、迁 R2 或双读迁移。

## 11. 下一步

下一次实施应只做 **P0-A：跨平台合同与 Restaurant Identity**：先添加 JSON contract tests、D1 `0015` 增量 migration、Worker 兼容适配和 iOS DTO/ID 映射测试。完成并分别通过 Web 与 iOS build/tests 后，再进入原生认证与双向同步；不要同时开始发现、Premium 或统计 UI。
