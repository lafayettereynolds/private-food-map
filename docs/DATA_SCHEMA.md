# Taste Map 数据结构

更新时间：2026-08-22

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

## 数据库版本与迁移

- Dexie v12：补齐到访体验标签数组与用户地图可见性。
- Dexie v13：补齐预设头像、会员等级和 `diningOccasionText`；只做增量默认值迁移，不清空数据。
- Dexie v14：把旧 `diningOccasion` 单值增量转换为 `diningOccasions` 数组，并保留首项兼容镜像。
- D1 `0005_visit_tags_and_map_privacy.sql`：体验标签与地图可见性。
- D1 `0006_avatar_presets_and_membership.sql`：预设头像、会员等级和自定义适合场景。
- D1 `0007_multi_dining_occasions.sql`：新增 JSON 格式的多选适合场景，并从旧单值字段迁移现有记录。

正式数据库不得通过删除、清空或改名解决 schema 问题；所有变更继续使用增量 migration。
