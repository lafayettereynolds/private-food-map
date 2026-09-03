# Taste Map UGC Restaurant Visual System — Final Visual Closure

Date: 2026-09-03

Branch: `feature/hybrid-ugc-restaurant-visuals`

Scope: Map, Add Restaurant Search/Nearby/Share preview, Restaurant Detail, and Discovery (`关注 / 为你推荐 / 同味之选 / 最新 / 趋势`)

Production state: unchanged (`NATIVE_PRIMARY`)

## Engineering Status

Implemented one typed, surface-aware Restaurant visual architecture:

`Restaurant identity → eligible RestaurantUGCImagePool → surface policy → typed descriptor → React/Native renderer`

The typed result is one of `ownerPhoto`, `activityPhoto`, `publicUGC`, or `foodCategoryVisual`. Photo descriptors retain safe resource identity plus photo, Restaurant, Visit, source-owner, visibility, attribution, and export metadata when applicable. React receives neither raw filesystem paths, image binaries, storage credentials, nor provider credentials.

Discovery and Community photo candidates are loaded in grouped Worker queries, joined to Visit/Profile/Restaurant state, grouped by Restaurant identity, and selected deterministically. There is no per-card PhotoAsset query. Native Map/Search/Nearby reads remain authenticated-owner scoped. Search and Nearby share the same resolver plan.

No AMap merchant-photo service, key, security code, Web Map, new third-party image source, Production write, SwiftData schema change, or App Icon change was introduced. Apple `MKLocalSearch` remains the iOS candidate provider; iOS Map remains Native MapKit.

## Food Category Visual Contract

The stable cross-platform IDs are:

| ID | Product meaning | Typical matching evidence |
| --- | --- | --- |
| `chinese` | 中餐 | 中餐、中国菜、杭帮/江浙/本帮及地方菜系 |
| `japaneseKorean` | 日料 / 韩餐 | 寿司、刺身、居酒屋、韩式、Japanese/Korean |
| `western` | 西餐 | 意法餐、牛排、披萨、Pasta/Bistro |
| `hotpotBBQ` | 火锅 / 烧烤 | 火锅、涮、烤肉、串烧、BBQ |
| `noodles` | 面 / 粉 / 饺馄 | 拉面、拌面、米线、河粉、饺子、馄饨 |
| `cafeBakery` | 咖啡 / 烘焙 | Coffee/Cafe、面包、Bakery、Brunch |
| `drinksDessert` | 饮品 / 甜品 | 奶茶、茶饮、蛋糕、冰淇淋、Dessert/Boba |
| `seafood` | 海鲜 | 海鲜、鱼生、生蚝、龙虾、螃蟹 |
| `fastFood` | 小吃 / 快餐 | 汉堡、炸鸡、便当、简餐、Fast Food |
| `vegetarianLight` | 素食 / 轻食 | 素食、沙拉、健康餐、Vegan/Healthy |
| `other` | 其他餐饮 | 没有可靠分类证据时的诚实 fallback |

Mapping consumes available Restaurant name, existing tags/cuisine evidence, and provider POI category. It uses NFKC normalization, ordered keyword matching, and a stable fallback. React SVG and Swift/UIKit vector renderers share the same IDs and palette families. Assets are local, deterministic, non-emoji, and network independent.

## Product Contract Status

| Surface | Final source order | Identity semantics |
| --- | --- | --- |
| Personal Map | current-owner marker/Restaurant/Visit photo → category visual | Never uses another user's UGC; marker upgrades when the owner adds a photo |
| Add Search / Nearby | matched current-owner photo → eligible public Taste Map UGC → category visual | Search and Nearby use the same resolution; a new MapKit candidate honestly uses category |
| Share candidate / preview | same acquisition descriptor contract as Search/Nearby | No independent `photoURL ? image : fallback` resolver |
| Restaurant Detail | current-owner photo → eligible public UGC → category visual | Existing canonical Detail IA is retained |
| 关注 | viewer-visible activity photo → public Restaurant UGC → category visual | Author/photo association is valid because the card is a real followed activity |
| 为你推荐 | current-owner photo → public Restaurant UGC → category visual | Uploader is not displayed or inferred as recommender; reason remains algorithmic |
| 同味之选 | same-taste Visit/activity photo → public Restaurant UGC → category visual | Source user/rating/Visit may be shown because the relationship is real |
| 最新 | latest viewer-visible activity photo → public Restaurant UGC → category visual | Activity author relationship is real |
| 趋势 | current-owner photo → public Restaurant UGC → category visual | Uploader is not displayed or inferred as trend source |

Map independent-marker behavior remains unchanged: no numeric clustering; natural overlap; deterministic layer order `selected → rating → visitCount → stable Restaurant ID`; real MapKit pan/pinch/viewport; circular user-avatar location marker.

## Permission and Lifecycle Status

Public UGC requires an active PhotoAsset and active Restaurant, a public Photo visibility, public attached Visit visibility when a Visit exists, and a public Profile. Deleted/binary-deleted assets and actioned moderation reports are rejected. Worker queries exclude users blocked in either viewer/author direction. Friends/limited content is not admitted to the global public pool; it may be selected only for an activity the authorized viewer can see. Current-owner private content is readable only on owner-scoped surfaces.

Eligibility is derived at read/resolution time. A Photo deletion, Visit deletion/visibility downgrade, Profile/account removal, moderation action, or block therefore removes the record from the next projection instead of leaving a permanent cover reference. Deterministic order is marker preference, explicit sort order where available, recency, then stable photo ID.

Other-user public UGC is in-app visual material with `exportAllowed = false`. It is excluded from automatic share/Analytics poster, download, Backup, and external-share asset selection. Current-owner photos retain the existing owner export contract.

## Visual Status

Browser evidence was captured from the real shared React build:

- `evidence/ugc-restaurant-visuals/browser-add-search.png`: multiple new MapKit-style candidates resolve to different fixed category visuals.
- `evidence/ugc-restaurant-visuals/browser-map.png`: owner photo and category marker language in one map composition.
- `evidence/ugc-restaurant-visuals/browser-discovery-for-you.png`: owner/public UGC/category mixture without uploader-as-recommender attribution.
- `evidence/ugc-restaurant-visuals/browser-discovery-trending.png`: public UGC/category mixture without uploader-as-trend-source attribution.
- `evidence/ugc-restaurant-visuals/browser-discovery-similar.png`: activity-specific image with the real same-taste source semantics.
- `evidence/ugc-restaurant-visuals/browser-discovery-latest.png`: activity-specific image with the real latest author semantics.

The iOS application built, installed, and launched on the required iPhone 17 Pro / iOS 26.5 simulator (`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`). `evidence/ugc-restaurant-visuals/simulator-map.png` records the real Native MapKit surface with owner food photos and local category markers visible together. The shared Capacitor Discovery surface was also inspected on this device and rendered the same public-UGC card treatment as Browser. A focused XCUITest attempt was interrupted by an iOS Simulator SpringBoard/XCTAutomation `EXC_BAD_ACCESS` while another worktree was using the same fixed device; this was infrastructure contention, not an app assertion or Taste Map crash. The App target and non-UI contracts pass independently.

## Regression Coverage

- Map: owner photo over category; no external merchant dependency; no other-user private photo.
- Search/Nearby: same resolver, owner reuse, public eligible UGC, category fallback for a new no-photo candidate.
- Discovery: all five tab priorities; uploader not recommender/trend source; activity-specific image for activity tabs.
- Permissions: public/profile/Visit gates, friend-only separation, owner isolation, deletion/moderation invalidation.
- Export: public other-user UGC is not automatically exportable.
- Cross-platform: stable category IDs, typed descriptor compatibility, Browser/Capacitor one-React rendering, safe native resource URLs.
- Performance: grouped photo hydration and existing large-dataset/Map browsing contracts.

Final validation:

- TypeScript application + Worker typecheck: PASS.
- Vitest: 60 files / 417 tests PASS.
- Swift Package bridge suite: 6 tests PASS.
- Xcode App target build on the fixed simulator: PASS.
- Focused Xcode suites (`RestaurantUGCVisualContractTests`, `MapBrowsingParityTests`, `Task10LargeDatasetPerformanceTests`): 22 tests PASS.
- Touched/new TypeScript lint: 0 errors / 0 warnings after separating the visual contract from its React component.
- `hybrid:stage:formal:debug`: PASS, including local-bundle foundation verification.
- Repository whitespace check: PASS.

The repository's pre-existing full ESLint run still reports unrelated legacy errors in files outside this change; this closure introduces no lint error.
