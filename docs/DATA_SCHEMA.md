# Taste Map 数据结构

更新时间：2026-08-28

## Restaurant JSON Contract V1

- 唯一合同文件为 `contracts/restaurant.v1.schema.json`；Web/Worker 使用 `src/contracts/restaurantContract.ts`，iOS 使用 `RestaurantJSONContractV1` 解码同一组 fixture。
- `id` 是 Taste Map 自己维护的稳定 Restaurant ID；`amap`、`apple_maps`、`manual`、`other` 仅作为 `placeIdentities` 中的 Provider identity。
- V1 必填且不可为 `null`：`schemaVersion`、`id`、`userId`、`placeIdentities`、名称/地址/城市/坐标、状态、偏好、标签、长笔记、Marker 类型/emoji、创建和更新时间。
- V1 必填但允许明确为 `null`：五项餐厅评分、参考人均、电话、营业时间、Marker Photo ID、商家图片 URL、删除时间。
- V1 可选且不可为 `null`：仅为旧 Web 兼容保留的 `amapPoiId` 和测试标记 `isTestData`。新客户端不得从 `amapPoiId` 生成 Restaurant.id。
- 缺少 `schemaVersion/placeIdentities` 的旧 Web payload 仍可读取；解码层会把非空 `amapPoiId` 映射为一条主 `amap` identity，再按 V1 输出。

## Visit 本轮相关字段

- `diningMode`: `dine_in | takeout`，描述单次到访的到店/外卖方式。
- `visibility`: `private | friends | public`；原生默认 `private`，公开接口仍需通过 Worker 权限过滤。
- `paymentMode`: `aa | my_treat | treated | separate | other | null`。
- `totalPrice`: 整桌账单，可空；不从 Dish price 推导。
- `myActualSpend`: 用户本人实际消费，可空；不由 paymentMode 推断。
- `pricePerPerson`: `totalPrice / partySize` 的四舍五入同步投影，可空且不直接编辑。
- `queueDuration`: `none | under15 | under30 | under60 | under90 | under120 | over120 | null`；`none` 表示明确 0 等位，`null` 表示未记录。
- `diningOccasions`: 适合场景数组，支持多选；自定义场景时包含 `other`。
- `diningOccasion`: 兼容旧客户端的首项镜像字段；新逻辑以 `diningOccasions` 为准。
- `diningOccasionText`: 自定义适合场景文字，旧记录迁移为空字符串。
- `valueTags`、`serviceTags`、`environmentTags`: 可多选并允许自定义的体验标签数组。
- `diningDuration`: 上餐时长，可选 `under15`、`under30`、`under45`、`under60`、`under90`、`under120`、`over120`。
- `noiseLevel`: `quiet | normal | loud | very_loud | null`。
- `portionLevel`: `small | normal | generous | null`。
- `transportConvenience`: `very_convenient | convenient | normal | inconvenient | null`。
- `specialNotes`: 最低消费、现场规则等可选文字；与一般 `note` 分开。
- P2-E 的完整 Web→iOS 字段矩阵、nullable 合同与 legacy 保真策略见 `P2_E_DINING_CONTEXT.md`。
- P2-F 的饭搭子/推荐来源 identity、Visit snapshot 投影、同步顺序及 migration 风险见 `P2_F_COMPANIONS_RECOMMENDATION_SOURCES.md`。

## UserProfile 本轮相关字段

- `avatarPresetId`: 16 个预设头像之一，默认 `polar-bear`。
- `membershipTier`: `free | member`；服务端为权限真值来源。
- `mapSharingEnabled`: 是否对外显示个人地图。
- `mapVisibility`: `private | friends | public`，统一控制地图可见范围。

## 饭搭子与发现数据

- `Visit.companionIds`: 单次到访关联的历史饭搭子 ID 数组；旧 `companions` 文本继续兼容展示。
- `DiningCompanion`: 用户自己的历史饭搭子，可选关联真实 `linkedUserId`；未关联账号时可使用可选的 `privateAvatarData` 保存私人头像、`relationshipLabel` 保存关系备注。
- `CompanionLinkRequest`: 饭搭子身份关联邀请，状态为 `pending | accepted | rejected`。
- `Follow`: 单向关注关系，由 `followerId` 与 `followedUserId` 唯一确定。
- `WantToGo`: 用户与餐厅的想吃关系。
- `isTestData` / `isTestUser`: 仅供开发环境的可清理测试数据标记，不作为正式业务状态。

## 本轮新增的跨平台实体

- `MembershipEntitlement`: 服务端会员权益，包含来源、起止时间、终身标记、状态、备注和审计元数据；客户端 `membershipTier` 只是有效权益的投影。
- `MembershipAuditLog`: 记录会员赠送、延期和撤销的操作者、目标用户、变更前后值与原因。
- `Photo`: 新增通用 `storageProvider`、`storageKey`、缩略图 Key/大小、`visibility` 与 `syncStatus`；旧 Drive ID 增量映射为默认存储 Key。
- `SyncQueueItem`: 使用独立 `operationId`、动作、状态、尝试次数、下次重试时间和错误信息，支持幂等增量同步。
- `RecommendationEvent`: 记录推荐类型、页面、餐厅、位置、得分、原因码和事件时间，不把事件统计写进 React 页面状态。
- `RestaurantListCollection`: 用户命名的食单，包含简介、可见范围、普通/排名模式、自动/自定义封面及软删除时间。
- `RestaurantListItem`: 食单与 Global Restaurant ID 的关联，包含位置和单项笔记；`[listId+restaurantId]` 唯一。
- `RestaurantPlaceIdentity`: Restaurant 与地图/人工来源标识的映射，字段为 `restaurantId`、`userId`、`provider`、`externalId`、主标识状态及审计时间；Provider ID 不是业务主键，每个 Restaurant 最多只有一个主映射。
- `SyncMutationReceipt`: 按认证用户和 mutation ID 唯一保存请求 fingerprint、处理状态、实体版本与 revision，保证响应丢失后的重试不会重复写入。
- `SyncChangeLog`: Restaurant/Visit 每次有效变化对应一个递增 revision，作为 V1 增量 pull cursor；旧 Web 的真实写入也进入同一日志。
- iOS `SyncMutation`: SwiftData 持久化离线 mutation、payload、base version、重试和 conflict 状态；`SyncCheckpoint` 持久化 V1 cursor。

## 数据库版本与迁移

- Dexie v12：补齐到访体验标签数组与用户地图可见性。
- Dexie v13：补齐预设头像、会员等级和 `diningOccasionText`；只做增量默认值迁移，不清空数据。
- Dexie v14：把旧 `diningOccasion` 单值增量转换为 `diningOccasions` 数组，并保留首项兼容镜像。
- Dexie v15：增加饭搭子实体、饭搭子身份关联邀请和 Visit 的 `companionIds`，把旧文本饭搭子增量整理为本地实体。
- 2026-08-26 兼容扩展：`DiningCompanion.privateAvatarData` 与 `relationshipLabel` 为非索引可选属性，Dexie 表结构和索引未变化，因此不升数据库版本；旧记录读取为 `undefined` 并按默认头像/空关系降级。
- Dexie v16：增加单向关注和开发测试数据标记；不会自动向正式环境写入模拟数据。
- Dexie v17：为同步队列增加状态/重试索引并加入图片缓存表。
- Dexie v18：为 Photo 增加平台无关的存储、缩略图、可见性与同步状态，并为旧记录补齐默认值；同步队列补齐幂等操作字段。
- Dexie v19：增加 `restaurantLists` 和 `restaurantListItems`，同一食单内同一餐厅保持唯一。
- D1 `0005_visit_tags_and_map_privacy.sql`：体验标签与地图可见性。
- D1 `0006_avatar_presets_and_membership.sql`：预设头像、会员等级和自定义适合场景。
- D1 `0007_multi_dining_occasions.sql`：新增 JSON 格式的多选适合场景，并从旧单值字段迁移现有记录。
- D1 `0008_dining_companion_links.sql`：增加饭搭子实体、身份关联邀请和 Visit 饭搭子 ID 数组。
- D1 `0009_discovery_follows_and_test_markers.sql`：增加单向关注、想吃关系及开发测试数据标记。
- D1 `0010_membership_entitlements.sql`：会员权益与管理员审计日志。
- D1 `0011_photo_storage_metadata.sql`：图片通用存储 Key、缩略图、可见性与同步状态。
- D1 `0012_recommendation_events.sql`：推荐曝光、点击和转化事件。
- D1 `0013_restaurant_lists.sql`：食单与食单餐厅项。
- D1 `0014_restaurant_contact_details.sql`：为餐厅增加电话与营业时间字段，供 Web、未来 iOS 与同步接口共同读取。
- D1 `0015_restaurant_place_identities.sql`：新增 Provider-neutral 餐厅身份映射表和查询索引，从现有非空 `amap_poi_id` 一对一回填映射；不修改 Restaurant/Visit 主键、不自动合并重复 POI、不改写 Visit 外键。
- D1 `0016_sync_v1.sql`：为 Restaurant/Visit 增加服务端版本和最后 mutation，新增 change log 与 idempotency receipt，并为既有记录写入 version 1 bootstrap 事件；空 Provider 旧记录补一条 `manual/tastemap:<id>` identity，不改写原 ID 或 Visit 外键。

Development 与 Production D1 的已知基线均已按顺序增量应用到 `0014`。`0015`、`0016` 目前只完成代码和本地迁移验证，尚未远程应用；部署前必须使用 `scripts/sql/restaurant_identity_preflight.sql` 对目标 D1 做只读检查。没有删除、清空或重命名数据库。

正式数据库不得通过删除、清空或改名解决 schema 问题；所有变更继续使用增量 migration。
