# Taste Map — Task 09 Acceptance Report

## Outcome

Task 09 closes the non-product accessibility, Dynamic Type, Dark Mode, Chinese locale, and long-content quality pass without changing Product IA. It also establishes a deterministic, `DEBUG`-only Visual QA environment so the same fixed Simulator can be used to inspect rich logged-in and Premium states instead of mistaking empty/login gates for finished UI.

## Accessibility and Dynamic Type

- The shared five-item primary tab component now preserves the approved equal-width product layout at standard content sizes and automatically changes to a horizontally scrollable layout at accessibility sizes.
- Selected state is exposed through accessibility traits and readable selected/unselected values, rather than color alone.
- Tab hit targets remain at least 44 pt; long labels may use two lines instead of being clipped.
- The My Map title/switch group remains centered as one unit and supports long text and accessibility sizes.
- The existing semantic labels for the Map/List switch remain `切换到我的列表` and `切换到我的地图`.
- Existing Restaurant markers, filter chips, poster controls, icon-only navigation/actions, and rating/sample semantics were audited; no new ambiguous decorative icon was introduced as an interactive control.

## Dark Mode

- Core App continues to use semantic colors, borders, and selection states.
- Existing dark-layout regressions for Map, Discovery, and Profile pass.
- Analysis posters intentionally remain on their approved fixed light poster theme; surrounding preview/share controls continue to use Core App semantic styling.
- No global theme or Product IA was redesigned.

## Chinese locale and dates

- Added one centralized display formatter for abbreviated date/time, numeric date/time, year/month, month/day, and relative labels using `zh-Hans-CN` and the current calendar/time zone.
- Replaced user-visible ad-hoc `.formatted(...)` output in Sync, Premium, Import, Community, Social/Profile, Settings, Restaurant, Dish, Discovery, and Visit surfaces.
- The formatter affects presentation only. API contracts, ISO-8601 payloads, UTC storage, sync cursors, and timestamps are unchanged.
- Automated coverage rejects unexplained English month leakage in the Chinese UI.

## Long and boundary content

Visual QA exposes deterministic modes:

- `empty`
- `normal`
- `rich` (default acceptance state)
- `very-rich`
- `long-text`
- `missing-photo`
- `error`
- `offline`
- `free`

Long usernames, restaurant names, addresses, list titles, companions, recommendation sources, currency totals, and large statistics are generated deterministically. Error/offline modes do not silently fall back to a successful network response.

## DEBUG-only Visual QA / Rich Demo Mode

Launch the fixed Simulator in the default rich state:

```sh
SIMCTL_CHILD_TASTEMAP_VISUAL_QA_MODE=rich \
xcrun simctl launch --terminate-running-process \
E4F3EED9-89D8-405C-B4CB-7CA816CE3405 \
com.lafayette.tastemap
```

Change `rich` to any mode listed above. The Visual QA runtime:

- uses a fresh in-memory SwiftData container;
- uses an isolated temporary photo root;
- never consumes the real Share Extension import queue;
- does not read or write the real Keychain;
- does not use Apple Sign In, a fake Worker auth bypass, or a fake App Store transaction;
- disables automatic network/sync services;
- never writes Development or Production backend data;
- is compiled only under `#if DEBUG`.

### Default rich counts

| Fixture | Count |
|---|---:|
| Visited restaurants | 90 |
| Want-to-go restaurants | 25 |
| Visits | 275 |
| Local fixture photos | 60 |
| Dishes | 130 |
| Dining companions | 10 |
| Recommendation sources | 12 |
| Lists | 7 |
| Following | 48 |
| Followers | 73 |
| Discovery/community feed items | 12 per rich surface |

The restaurants cover Apple Maps-only, AMap, and manual identities; visited/want-to-go, long names, missing photos, phones, hours, price, ratings, dishes, visits, and user-photo states. Images are deterministic local fixtures used as restaurant images; the normal real-image-first pipeline remains unchanged.

## Visual QA Premium entitlement

The default `rich`, `very-rich`, `long-text`, `missing-photo`, `error`, and `offline` demo user is locally presented as `Premium Active`. `free` uses the same safe fixture architecture with a Free entitlement to inspect Paywall and locked states.

The Premium fixture uses the existing entitlement abstraction and unlocks the exact current `PremiumFeatureRegistry`:

- 完整口味档案
- 最佳饭搭子
- 谁最会种草
- 同味能力
- 深度个性化推荐
- 高级推荐筛选
- 本月回顾
- 年度食味年鉴
- 消费洞察
- 饭搭子选餐
- 自定义头像
- 更多到访照片

Profile displays the existing approved Premium hamburger badge. Formal StoreKit/server entitlement behavior is unchanged.

## Release binary purity

Release Simulator build succeeded for the main app and Share Extension. A string scan of both binaries confirmed absence of:

- `TASTEMAP_VISUAL_QA_MODE`
- `TasteMapVisualQA`
- `visual-qa`
- the rich demo identity and fixture strings
- Visual QA Premium override identifiers
- isolated test credential/network blocker implementations
- UI-test/test-auth activation keys

Therefore the Release binary has no Visual QA launch switch, fixture user, fake entitlement, test auth, or Premium bypass. Release Premium remains controlled only by the formal entitlement path.

Scan log: `/tmp/tastemap-task09-release-scan.log`

## Test and build evidence

| Check | Result |
|---|---|
| Task 09 unit suite | PASS — 4 tests |
| Rich logged-in Premium Visual QA UI path | PASS — Map → Discovery → Profile |
| Existing Dark Mode Map/Discovery/Profile UI regressions | PASS — 2 tests |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Production access | NONE |

Logs:

- `/tmp/tastemap-task09-unit-final.log`
- `/tmp/tastemap-task09-ui-final.log`
- `/tmp/tastemap-task09-dark-ui.log`
- `/tmp/tastemap-task09-debug-build.log`
- `/tmp/tastemap-task09-release-build.log`

Final UI attachments:

- [Rich Map](remaining-09-14-assets/task-09/ui-test-attachments-final/9237639B-DBEE-4900-BE0E-6F88C9F0BFE4.png)
- [Rich Discovery](remaining-09-14-assets/task-09/ui-test-attachments-final/9F92AFC1-B348-4025-8EE6-F3219C03C7AD.png)
- [Rich Premium Profile](remaining-09-14-assets/task-09/ui-test-attachments-final/AF6412E3-6DB6-4B55-AEAB-209A336971B5.png)

## Known follow-up routed to Task 10

The 90-marker rich Map intentionally makes the existing high-density individual-marker problem observable. No numerical cluster was introduced. Task 10 owns viewport culling, reuse, overlap/spiderfy behavior, and performance measurement while preserving the locked rule that Restaurant markers never become numeric clusters.
