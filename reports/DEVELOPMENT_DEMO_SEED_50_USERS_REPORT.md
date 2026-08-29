# Taste Map Development Demo Seed Data：50 用户最终验收报告

日期：2026-08-29

环境：Development only

Development Worker：`https://api-dev.tastemap.cn`

Development D1：`food-map-db-development`

Production：未访问、未查询、未迁移、未部署、未写入

## 1. 结论

50 个 Development-only 虚拟 Taste Map 用户的数据生成、远程 Seed/Clear/Reseed/Verify 基础设施和真实 Development Worker/D1 数据已经完成。

数据不是直接 SQL dump。Restaurant、Visit、Dish、List、Profile 等实体通过既有 Sync V1 写入，Friendship/Follow 通过既有 Social V1 authority 写入。数据集只生成原始行为，没有写入 similarity、trending、rank、推荐理由或算法输出。

真实 Development D1、增量 Sync Pull、正式 Similar Taste、正式 Trending、正式 Community 和 Public Profile 已完成远程验收。50 个账户的远程数据量符合要求；断网式重试和重复 Seed 没有产生业务副本。

## 2. Git baseline

- Branch：`main`
- 开始时 HEAD：`9b19ae9e15bacede918a3bbc83c33ae78663ac46`
- 开始时 `origin/main`：`9b19ae9e15bacede918a3bbc83c33ae78663ac46`
- 工作区原有未跟踪审计文档、既有 `reports/` 文件和 `pnpm-workspace.yaml` 均未删除、覆盖或混入本任务。

## 3. Development 安全边界

- Seeder 只接受完整 Base URL `https://api-dev.tastemap.cn`。
- 同时再次校验 hostname 必须为 `api-dev.tastemap.cn`。
- Worker admin route 只在 `APP_ENVIRONMENT=development` 且 `SYNC_AUTH_MODE=development-test` 时存在。
- Admin identity 固定为 `tm_demo_v2_admin`。
- Production、错误 host、错误环境、正式认证模式和非 admin identity 均 fail closed。
- Demo 用户没有 Apple identity，也没有使用真实 Apple `sub`。
- 未使用 Cloudflare、D1、R2 或 Apple Secret 写入客户端或 Git。
- 本任务没有直接对 Production 或 Development D1 执行业务写 SQL；远程 D1 命令仅用于只读统计和 migration preflight。

## 4. 固定 identity 与 namespace

- Namespace：`tm_demo_v2`
- Demo Users：`tm_demo_v2_user_01` 至 `tm_demo_v2_user_50`
- Shared Place identity：`manual:tm_demo_v2_place_001` 至 `manual:tm_demo_v2_place_360`
- Current User seed prefix：根据当前 Taste Map user ID 的 FNV-1a hash 派生，例如本次为 `tm_demo_v2_current_52ced2bf_*`
- 同一天 mutation ID 固定；重复请求由既有 Sync V1 mutation receipt 判定为 duplicate。

## 5. 实际用户分层

| 分层 | 用户范围 | 实际人数 | 设计用途 |
|---|---:|---:|---|
| Heavy | Demo 01–08 | 8 | Similar Taste、Trending、Community、Rich Profile |
| Normal | Demo 09–30 | 22 | Development 主体样本 |
| Light | Demo 31–42 | 12 | 低频普通用户 |
| Sparse / New | Demo 43–50 | 8 | 冷启动、证据不足和稀疏 Profile |
| 合计 | Demo 01–50 | 50 | — |

生成器测试逐用户验证了各层 Restaurant、Visit 和 WantToGo 范围，没有让 50 个用户使用相同规模。

## 6. 实际数据规模

### 6.1 Current User manifest

| 类型 | 数量 |
|---|---:|
| 去过 Restaurant | 90 |
| Visit | 275 |
| WantToGo Restaurant | 28 |
| Dish | 92 |
| List | 5 |
| Recommendation Source | 11 |
| Dining Companion | 9 |
| 全部 Sync manifest records | 545 |

远程只读交叉检查同时确认：当前真实用户原有的 2 家非 Seed Restaurant 和 2 条非 Seed Visit 仍然存在，没有被 Demo namespace 清理或 Seed 覆盖。

### 6.2 50 Demo Users

| 类型 | 目标 | 实际 |
|---|---:|---:|
| Demo User | 50 | 50 |
| 生成的共享 Restaurant universe | 300–400 | 360 |
| 远程实际被至少一个 Seed 账户引用的 unique place | 300–400 | 328 |
| 每用户 Restaurant records 合计 | — | 3559 |
| Visit | 4500–7000 | 4516 |
| WantToGo | 800–1200 | 1047 |
| Dish | 1000–1800 | 1512 |
| List | 70–120 | 84 |
| Friendship | — | 105 |
| Follow | — | 125 |
| Relationship 合计 | 150–250 | 230 |

`360` 是完整确定性候选 universe；本次 51 个账户实际选择并写入了其中 `328` 个 unique provider-neutral place identity。两者都处于 300–400 的要求范围内。

Dish 通过既有 Worker Dish upsert 逻辑建立兼容 VisitDish 关联；Seeder 不再重复发送第二条同一 `(visit_id, dish_id)` 关联，从而避免唯一约束冲突。

## 7. 可见性、时间窗口与城市

### 7.1 Visit visibility

| Visibility | 实际数量 | 比例 |
|---|---:|---:|
| Public | 2478 | 54.87% |
| Friends | 1141 | 25.27% |
| Private | 897 | 19.86% |
| 合计 | 4516 | 100% |

### 7.2 动态时间窗口

- 7 天内活跃 Restaurant：37
- 30 天内活跃 Restaurant：57
- 另有历史热门 cohort，其 Visit 全部早于 30 天窗口。
- Visit 时间以当天 `referenceNow` 为基准；同一天生成一致，跨天 Reseed 时窗口自然向前移动。

### 7.3 360 家候选 universe 城市分布

- 杭州：207（57.5%）
- 上海：36（10%）
- 北京、成都、广州、东京、大阪：各 18（各 5%）
- 南京、厦门、首尔：各 9（各 2.5%）

所有 Restaurant 名称都显式含“虚构”，地址显式含“虚构”；没有真实商户电话、真实商户图片或网络抓图。

## 8. Similar Taste 原始输入梯度

以下是 Current User 与各组的 shared Restaurant count；它们是算法输入，不是 Seed 的 similarity score：

| Group | Demo Users | 实际 overlap |
|---|---|---|
| S | 01–08 | 87, 86, 84, 82, 81, 78, 75, 74 |
| A | 09–16 | 50, 51, 52, 53, 52, 52, 55, 53 |
| B | 17–26 | 41, 37, 37, 32, 35, 34, 41, 35, 38, 37 |
| C | 27–36 | 16, 15, 17, 15, 12, 12, 11, 11, 12, 10 |
| D | 37–42 | 5, 5, 6, 6, 4, 5 |
| E | 43–50 | 2, 3, 3, 5, 5, 3, 4, 3 |

Demo 01/02 拥有最强的共享输入。但正式 Similar Taste 推荐会排除 Current User 已经访问的餐厅，因此“输入最相似用户”不保证必然成为“剩余可推荐餐厅最多的 source user”。实际结果按正式算法记录，不为满足预期而改算法或硬编码排名。

## 9. 正式算法真实结果

真实 Development Worker 的最终 Verify 结果：

- Similar Taste：38 个结果。
- Similar Taste 首批 source users 包含 Demo 14、08、05、10、06 等；没有写固定 source 或 similarity。
- Trending 7 day：36 个结果。
- Trending 30 day：50 个结果。
- 7 day 与 30 day 的 Global Restaurant identity 集合不相同，窗口差异验证通过。
- Community 首屏：50 条 Visit activity，来自 22 个不同用户。
- Public Profile / content：
  - Demo 01：147 条可见 Visit，分页返回 10 条。
  - Demo 18：99 条可见 Visit，分页返回 10 条。
  - Demo 31：通过已接受 Friendship 正确看到 friends-only Profile，33 条可见 Visit，返回 10 条。
  - Demo 45：Sparse Profile，5 条可见 Visit，返回 5 条。

最后一次逐接口远程 smoke 均为 HTTP 200：Similar Taste 约 2.59 秒、7-day Trending 约 1.83 秒、30-day Trending 约 2.09 秒、Community 约 1.80 秒。并发高峰时 Cloudflare 仍可能短暂返回 503，Seeder/Verifier 已使用受控并发和指数退避处理。

## 10. Idempotency 与重复 Seed

- mutation ID、entity ID、demo user ID 和 place identity 都是确定性的。
- 同一 mutation 重复发送由 `sync_mutation_receipts_v6` 返回 duplicate，而不是再创建实体。
- 实际远程过程中发生过响应丢失式重试、进程续跑和重复 Seed。
- D1 最终仍精确保持 50 profiles、3559 Restaurant records、4516 Visit、1512 Dish、84 List；没有 `copy` 用户或重复业务记录。
- Demo receipt 数为 10633，说明完整实体集合由已有 Sync 幂等账本覆盖；重复发送不会改变业务计数。

## 11. Cleanup 设计与安全边界

Development admin API：

- `GET /api/v1/development/demo-data/summary`
- `DELETE /api/v1/development/demo-data`

Demo 清理由 50 个精确 user ID allowlist 驱动，不按昵称、日期、数量、Restaurant 名称或 `is_test_data` 模糊删除。

Current User 清理只接受调用方提交的 DevelopmentSeedManifest，并逐项验证 entity ID 必须以该 user 派生的精确 prefix 开头。任何越界 ID、重复 ID、demo/admin current user 或格式错误 identity 都会被拒绝。

清理覆盖 Seeder-owned Restaurant identity、Restaurant、Visit、Dish、Worker 自动创建的 VisitDish、List/ListItem、Recommendation Source、Companion、Sync ledger 和 Current↔Demo social edges。清理完成后还会断言 50 个 demo users 为 0，并断言当前真实用户仍存在。

本次远程 cleanup 在一次 Reseed 尝试中已经成功完成。该次“cleanup 完成到随后首个 current push 失败”的组合上界为 20.70 秒；因为随后 Seed 重试导致命令未打印正常结束 JSON，无法从现有日志精确拆分纯 cleanup 毫秒值。脚本已在正常结束报告中保留独立 `cleanupSeconds`，下一次单次 Reseed 会直接给出精确值。为了只补一个计时值而再次清空已经验收的数据风险更高，因此本轮没有再次破坏性清理。

## 12. 实际耗时

| 阶段 | 实际观测 |
|---|---:|
| Current User 首次 mutation processing span | 565.56 秒（约 9 分 26 秒） |
| 50 Demo Users 首次 mutation processing span | 1636.02 秒（约 27 分 16 秒） |
| 51 账户完整增量 Pull + 正式算法 Verify | 1716.33 秒（约 28 分 36 秒） |
| Cleanup | 小于 20.70 秒的远程组合上界；见上一节限制 |

前两项来自 D1 mutation receipt 的最早/最晚 `processed_at` 只读统计，反映首次成功处理跨度；不会把之后的 duplicate retry 计入首次写入时间。

## 13. Worker 性能硬化

50 用户完整数据首次暴露了 Discovery/Community 中数个 O(n²) lookup，在 Cloudflare Worker 上会触发 CPU/resource limit。

本轮只做输出等价的索引化：

- Discovery 将 first Visit、WantToGo place、viewer fingerprint 和最近 want 查找预先构建为 Map。
- Community 将 viewer/content fingerprint 对应关系预先构建为 Map。
- Taste Similarity 移除循环中的数组复制，改为原位追加。

没有修改：算法阈值、权重、排序、可见性、权限、返回 contract、推荐结果字段或数据库结构。原有算法回归测试与完整 Vitest 全部通过。

最终 Development Worker version：`0aa8033a-5678-4111-b12e-d099855a7628`。

## 14. 测试与构建

### 14.1 定向测试

- 5 test files passed。
- 38 tests passed。
- 覆盖 50 用户规模、分层范围、共享 universe、城市、S/A/B/C/D/E 梯度、动态窗口、评分/消费/可见性 persona、同日确定性、跨日移动、全部 Sync V1 decoder、精确清理、越界拒绝和 Production fail closed。

### 14.2 完整 Web/Worker 测试

- 44 test files passed。
- 315 tests passed。

### 14.3 TypeScript / Vite

- `tsc -b`：通过。
- Worker TypeScript `--noEmit`：通过。
- Vite production build：通过。
- 仅保留既有 500 kB chunk size 提示。

### 14.4 Lint

- 本任务新增和修改的脚本/Worker 文件 ESLint：通过，0 error / 0 warning。
- 仓库全量 lint 仍有 4 个与本任务无关的既有 error 和 1 个既有 warning，位置为 `backupV1.ts`、`dishPhotoContract.test.ts`、`photoBinaryV1.test.ts`、`CommunityPage.tsx`；本轮按 scope 未修改。

### 14.5 iOS

- TasteMap Debug iOS Simulator build：通过，`BUILD SUCCEEDED`。
- Bundle Identifier 仍为 `com.lafayette.tastemap`。
- 本任务没有修改 iOS Target、Team、Signing、Capability、SwiftData 或 Sync contract。
- 系统当前列出 `Lafayette的iPhone`，但状态为 `unavailable`，因此本轮没有伪报真机页面滚动/视觉 smoke 已通过。

## 15. D1 / migration / Production

- Development D1 migration preflight：`No migrations to apply`。
- 新 migration：无。
- Schema change：无。
- Production Worker/D1：未访问、未查询、未迁移、未部署、未写入。

## 16. 新增/修改文件

### 新增

- `scripts/development-demo-data.mjs`
- `scripts/development-demo-data.test.ts`
- `scripts/seed-development-demo.mjs`
- `worker/developmentDemoAdminV1.ts`
- `worker/developmentDemoAdminV1.integration.test.js`
- `reports/DEVELOPMENT_DEMO_SEED_50_USERS_REPORT.md`

### 修改

- `scripts/seed-test-users.mjs`
- `package.json`
- `worker/index.ts`
- `worker/discoveryV1.ts`
- `worker/communityV1.ts`
- `worker/tasteSimilarity.ts`
- `docs/TEST_DISCOVERY_DATA.md`
- `docs/PROJECT_STATE.md`
- `docs/CHANGELOG.md`

## 17. 使用命令

```bash
export TASTEMAP_API_DEV_BASE_URL=https://api-dev.tastemap.cn
export TASTEMAP_DEVELOPMENT_CURRENT_USER_ID=<Development Taste Map user ID>

pnpm run seed:test-users
pnpm run reset:test-users
pnpm run reseed:development-demo
pnpm run verify:development-demo
```

命令在 `--environment development`、准确 Development URL 和有效 current user identity 缺任一项时都会立即失败，不会 fallback 到 Production。

## 18. 剩余人工验收

后端数据和产品算法链路已经完成。待 iPhone 再次显示为 available 后，建议进行一次不改数据的手工 smoke：

1. 打开 Similar Taste，确认能连续看到多层候选。
2. 对比 7 日与 30 日 Trending。
3. 滚动 Community，确认用户、Restaurant、时间和内容有差异。
4. 打开 Demo 01、18、31、45 的 Public Profile，确认 Rich/Normal/Friends-only/Sparse 差异。

这项只属于真机视觉与交互确认，不影响本报告中已经完成的真实 Worker/D1、同步和算法验收结论。
