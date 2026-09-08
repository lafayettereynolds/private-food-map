# Account deletion regression closure / preserved Apple lifecycle

日期：2026-09-09。项目 `/Users/lafayette/Projects/private-food-map-hybrid-final-integration`。仅本地迁移 SQLite、mock R2、Native Simulator 与审计用 Release device build；无 Production D1/R2 请求、无部署、无手机安装、无 Cutover/Archive/TestFlight。

## 基线与保护

- Apple lifecycle 独立 commit：`d3ea340` — `Handle Sign in with Apple credential revocation lifecycle`。
- 原先的 retention / account deletion 修复已在本轮开始前提交：`0b02beda2ec8a90a64611943077e070e6b6a39b4` — `Fix account object cleanup and add bounded privacy retention lifecycle`。后续 HEAD 还有独立网站/隐私文档提交，不是本任务的修改。
- Apple commit 逐 hunk 提交 10 个文件。共享文件中的 Referral、Discovery、Private Preview renderer 及 device log 改动留在工作区，未混入；未包含 Worker privacy/deletion 代码。
- 为避免新增依赖未提交的 DeviceAcceptanceLog，仅把本轮新增的 Keychain 清理错误日志改为既有 authDebug；不改变认证行为。
- 先行安全副本：`/tmp/tastemap-deletion-closure.bSnhd8/apple-safety.tgz`；共享文件原始 diff：同目录 `apple-workspace-before.patch`；提交选择补丁：`apple-only.patch`。未 reset/stash/清除工作区。
- 本报告所在后继 commit 仅增加 account deletion/retention 回归与报告，不把 Apple lifecycle 和其他窗口改动再次混成一个提交。

## 原 3 条失败的实际根因与现状

历史失败数 3；**本轮第一次复跑已经是 0**（Auth + Release Safety + Retention：27/27）。不是本轮先复现红灯后修改业务代码；原问题已由 `0b02bed` 处理，保留真实时间线。

1. 同 Apple identity 删除后重新注册：旧 Auth test environment 没有 PHOTO_STORAGE；新完成条件必须执行 fresh R2 prefix list，故 job 返回失败，未走 finishDeletion 的 Apple identity 解绑。现已提供有效空 bucket mock，完成后移除旧 auth identity mapping，后续签名身份得到全新随机 Taste Map userID。
2. D1/R2 完成幂等：旧 MemoryR2Bucket 没有 list，并按单 key 记录删除；新算法需要批量 delete 与 fresh empty listing。mock 已跟随实际 R2 合约实现，不绕过生产中的最终零对象证明。
3. R2 失败恢复：旧 expectation 要求 users.deleted_at 仍 null，与现行“立即锁定账号、清认证/公开可见性、保留 retryable 清理任务”相冲突。已更正为 deleted_at 有值，但 completedAt 仍 null、status failed/retryable true；opaque status token 可恢复清理。

因此没有回退 30/90/365 retention、恢复立即 hard-delete-everything 或放宽 R2 完成条件来刷绿。

## 完成条件 / retention 的区别

ACCOUNT USER DATA CLEANUP COMPLETE：账号不可继续认证；D1 业务行进入既定不可见/删除状态；原图与缩略图队列处理完；owner prefix fresh list 无对象且不 truncated；pending object queue=0；最后才写 completed/last_error_code=null。

LEGAL/RETENTION RECORDS REMAINING：旧业务 tombstone、旧 user shell、仍在期限内的 audit/commerce rows 可以保留，但 owner 仍是旧 userID，不构成未完成，也不迁移到重注册账号。retry_count 保留历史尝试次数供审计，不是待重试状态；完成后的 retryable=false、errorCode=null。已有 lease 与 completed guard 使重复 confirm 不再次执行 object deletion，不重写完成结果。

删除仅使用 `users/<validated-owner>/photos/` 前缀；队列 metadata 若指向他人前缀则 fail closed。批量部分失败后 idempotent delete 重试，重新 list 最终证明为空；不是看“返回短页”就完成。

## 本轮补强的回归

`worker/authV1.integration.test.js` 的重注册用例现在先真实建立旧私有 Restaurant/Visit/Photo、qualified referral/reward、lifetime Gift 和 audit：

- 删除完成后相同 Apple identity 可再次 exchange，新 userID 不同，旧身份不永久占用。
- 旧私有行 tombstoned，旧 Gift/audit 仍归旧 userID；新账号无旧内容/Gift/reward/referral。
- 用新 access token 执行真实 handler sync pull 并检查 JSON，不让 Response 对象空序列化变成空泛断言。
- 另一 referrer 的奖励仍在，不能删除他人权益。

`worker/privacyRetentionV1.integration.test.js` 新增：

- 2,502 个 original/thumbnail 混合对象，第 20 个 delete batch 中途真实移除部分对象后抛错；失败后仍余 >1,000 个，retry 最终零对象并保留 B 的对象。
- 有合法 retained membership audit row 时仍 completed；重复 job 不新增 delete 调用，完成结果保持一致。
- 30 天 content、90 天 security、365 天无其他依赖的 closed-account shell：阈值前 1ms 保留，到达阈值按规则清理。

既有 0/1/999/1000/1001/2502 对象、错误 owner、最终 proof 非空、R2 失败键保留、sync tombstone/旧设备 resurrection 拒绝、active Apple transaction、跨账号 reward 依赖测试均保留。

## 验证状态

证据目录：`/tmp/tastemap-deletion-closure.bSnhd8`，为私有临时目录，系统可清理，不是 release archive。

| 项目 | 结果 | 证据 |
|---|---|---|
| 原 3 条 Worker 回归 | PASS，历史 3 → 本轮首次 0 | before.log |
| 全 Worker | PASS，382 tests / 38 files，0 skip/pending | worker-verified.log |
| Native Apple/Auth/Account + F1-C4 | PASS，31 tests / 4 suites | native.log；Native/Logs/Test/*.xcresult |
| Swift native bridge package | PASS，42 tests，0 failures | swift-package.log |
| TypeScript app + Worker | PASS | tsc -b；tsc -p tsconfig.worker.json --noEmit |
| Release iPhoneOS main + extension | BUILD SUCCEEDED | release.log |
| Release capability audit | 44/44 PASS | capability.json |
| Embedded identity / codesign / provisioning | PASS | identity.json |
| 全仓正式源码 Vitest | 1504 total：1501 PASS / 3 FAIL，0 pending/todo；未跳过当前源码用例 | full-final.json / full-final.log；见下节 |

首次未限定目录的 Vitest 还抓到了 `.private/privacy-production-candidate` 的历史部署副本，产生重复测试和过期 migration/referral 断言。这不是当前源码 target；后续使用 `--exclude '**/.private/**'` 去除私有归档副本，**没有 skip 当前源码中的任何测试，也没有隐藏真实的 3 条 Hybrid/UI 失败**。

## 全仓剩余范围（不属于删除逻辑）

- `HybridQACompanionContract.test.ts` 两条断言仍要求 Private Preview 在 DEBUG 内且有 `DEBUG TASTEMAP_PRIVATE_PREVIEW`，当前批准的配置为独立 `TASTEMAP_PRIVATE_PREVIEW`；正式 Release 仍 Native。
- `SettingsInteractionContract.test.tsx` 仍要求旧“对应记录中修改”文案，当前页面已采用主页/味觉足迹/到访照片统一 visibility 文案。

已集中请求用户确认是否仅更新这些旧测试断言；在授权前不擅自改变 UI、renderer、product rules 或测试 expectations。账号删除、Apple lifecycle 不应因这些独立旧断言被回退。

## 状态原则

APPLE CREDENTIAL LIFECYCLE CODE：PASS。
ACCOUNT DELETION REGRESSIONS：PASS。
R2 ACCOUNT DELETION：PASS。
D1 RETENTION：PASS。
FULL AUTOMATION：在全仓 3 条独立断言关闭前不标 PASS。
REAL DEVICE APPLE LOGIN：PENDING。
REAL DEVICE APPLE REVOKE：PENDING。
REAL DEVICE TEST STILL REQUIRED：YES。

本轮没有新增 Production deployment、Final RC 或 TestFlight readiness 结论。

本轮审计产物：`/tmp/tastemap-deletion-closure.bSnhd8/Release/Build/Products/Release-iphoneos/TasteMap.app`，build 1 / version 1.0，沿用源码默认，仅本地审计，没有安装为测试候选。Development device signing，不是 Distribution/Final RC。
主可执行文件 SHA-256：`7ab2292cfb48a5aab94349ad03099d0363dc3277afdf0977eb718faddeaa7d6d`。
