# Development Demo Data v2

更新时间：2026-08-29

## 安全边界

- 只允许 `https://api-dev.tastemap.cn`，脚本会同时验证完整 Base URL 与 hostname。
- Worker 必须同时为 `APP_ENVIRONMENT=development`、`SYNC_AUTH_MODE=development-test`。
- Production、错误 host、缺少专用 `tm_demo_v2_admin` 身份时全部 fail closed。
- 不直接执行远程 D1 SQL dump；Restaurant、Visit、Dish、List、Profile 等都通过现有 Sync V1 写入，好友/关注通过 Social V1 写入。
- 50 个虚拟用户固定为 `tm_demo_v2_user_01`…`tm_demo_v2_user_50`，不使用 Apple identity。
- 当前用户样本记录使用 `tm_demo_v2_current_<user-hash>_*` manifest；清理只接受该用户派生出的精确 entity ID 前缀。
- Demo 清理使用 50 个精确 ID allowlist，不按昵称、日期、用户数量或 `is_test_data` 模糊删除。

## 固定数据规模

- 50 个虚拟用户：8 Heavy、22 Normal、12 Light、8 Sparse。
- 360 家完全虚构的共享 Restaurant universe；没有真实商户名称、电话或商户图片 URL。
- Current User：90 家去过、275 次 Visit、28 家想吃、92 道 Dish、5 个 List、11 个推荐来源、9 位饭搭子。
- Demo Users：约 4,500–7,000 次 Visit、800–1,200 家想吃、1,000–1,800 道 Dish、70–120 个 List、150–250 条社交关系。
- 同味输入分为 S/A/B/C/D/E 六层；只写 Restaurant/Visit/Rating 等原始行为，不写 similarity、trending 或 rank 结果。
- 7 日、30 日和历史活动由相对 `referenceNow` 的真实 Visit 日期形成。
- 同一天生成字节级稳定；跨天运行时活动窗口随日期推进。

## 必需环境变量

```bash
export TASTEMAP_API_DEV_BASE_URL=https://api-dev.tastemap.cn
export TASTEMAP_DEVELOPMENT_CURRENT_USER_ID=<Development Taste Map user ID>
```

第二项必须是 Development 中已有的真实/测试 Taste Map user ID，不能是 demo/admin ID。

## 命令

```bash
pnpm run seed:test-users
pnpm run reset:test-users
pnpm run reseed:development-demo
pnpm run verify:development-demo
```

- `seed`：幂等写入；同日再次运行只命中 mutation receipts，不创建副本。
- `clear`：只清理精确 Demo namespace 与 `DevelopmentSeedManifest` 中的 current-user records。
- `reseed`：先安全清理，再生成当天的确定性数据。
- `verify`：逐用户增量 pull 验证全部 manifest 记录，并调用正式 Similar Taste、Trending、Community、Public Profile API 检查产品输出。

当前 50 用户规模会真实分页读取 51 个账户。2026-08-29 的远程验收耗时约 29 分钟；命令会逐账户输出进度，避免长时间无反馈。这里的目标是 Development 数据正确性验收，不是压力测试。

可用 `--reference-now <ISO-8601>` 固定某个验收日；普通开发应省略，让当天趋势窗口自然前移。

## 照片说明

本数据集不伪造餐厅照片、不热链第三方图片，也不向 R2 写入假图片。Public Profile、Community 和 Discovery 的无图降级由现有正式产品逻辑处理。
