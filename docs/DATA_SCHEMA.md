# Taste Map 数据结构

更新时间：2026-08-24

## Visit 本轮相关字段

- `diningMode`: `dine_in | takeout`，描述单次到访的到店/外卖方式。
- `paymentMode`: `aa | host | guest | separate | other | null`。
- `totalPrice`: 总消费；“各付各的”时为 `null`。
- `myActualSpend`: 个人消费；仅“各付各的”使用。
- `diningOccasions`: 适合场景数组，支持多选；自定义场景时包含 `other`。
- `diningOccasion`: 兼容旧客户端的首项镜像字段；新逻辑以 `diningOccasions` 为准。
- `diningOccasionText`: 自定义适合场景文字，旧记录迁移为空字符串。
- `valueTags`、`serviceTags`、`environmentTags`: 可多选并允许自定义的体验标签数组。
- `diningDuration`: 上餐时长，可选 `under15`、`under30`、`under45`、`under60`、`under90`、`under120`、`over120`。

## UserProfile 本轮相关字段

- `avatarPresetId`: 16 个预设头像之一，默认 `polar-bear`。
- `membershipTier`: `free | member`；服务端为权限真值来源。
- `mapSharingEnabled`: 是否对外显示个人地图。
- `mapVisibility`: `private | friends | public`，统一控制地图可见范围。

## 饭搭子与发现数据

- `Visit.companionIds`: 单次到访关联的历史饭搭子 ID 数组；旧 `companions` 文本继续兼容展示。
- `DiningCompanion`: 用户自己的历史饭搭子，可选关联真实 `linkedUserId`。
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

## 数据库版本与迁移

- Dexie v12：补齐到访体验标签数组与用户地图可见性。
- Dexie v13：补齐预设头像、会员等级和 `diningOccasionText`；只做增量默认值迁移，不清空数据。
- Dexie v14：把旧 `diningOccasion` 单值增量转换为 `diningOccasions` 数组，并保留首项兼容镜像。
- Dexie v15：增加饭搭子实体、饭搭子身份关联邀请和 Visit 的 `companionIds`，把旧文本饭搭子增量整理为本地实体。
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

Development 与 Production D1 均已按顺序增量应用到 `0014`；没有删除、清空或重命名数据库，也没有重复执行已记录的 migration。

正式数据库不得通过删除、清空或改名解决 schema 问题；所有变更继续使用增量 migration。
