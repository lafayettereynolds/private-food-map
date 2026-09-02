# Taste Map｜Hybrid Remaining UI Batch 1 Closure

Date: 2026-09-03
Branch: `feature/hybrid-remaining-ui-batch`
Formal scope: Discovery/Community, Add Restaurant/Nearby UI, Lists, Roulette, Analytics/Posters, Premium and Settings, plus systemic App Shell and canonical Restaurant Detail integration regressions exposed during Batch 1.

## Outcome

Batch 1 is complete against the upgraded seven-gate definition. The work does not begin Batch 2 and does not deploy or access Production.

### 1. Discovery / Community

- exact first-level navigation: `关注 / 为你推荐 / 同味之选 / 最新 / 趋势`;
- centered compact hierarchy and shared FilterBar visual language;
- formal Browser and Capacitor consume the same Discovery scaffold and Activity Card;
- user/time, Restaurant image/info, Visit rating, Like/Comment/Share and Restaurant actions remain distinct semantic regions;
- Same Taste, loading, empty and error states retained;
- activity rating comes from Visit/activity data, never aggregate Restaurant rating.

Evidence:

- `screenshots/batch-01/browser-mobile-discovery-final.png`
- `screenshots/batch-01/discovery-capacitor-shared-after.png`
- five tab screenshots in `screenshots/batch-01/discovery-*.png`

Gates: UI FUNCTION **PASS** · BROWSER ↔ CAPACITOR VISUAL PARITY **PASS** · LAFAYETTE/FORMAL REFERENCE PARITY **PASS**.

### 2. Add Restaurant / Nearby

- one compact acquisition hierarchy shared by Browser and Capacitor;
- four formal capabilities: Search, Nearby, Share ingestion, Manual Add;
- no English eyebrow and no nested giant card layout;
- paste-link is not a primary flow;
- exactly one Manual Add entry;
- location unavailable/loading/error is an honest compact state, not missing UI;
- provider candidate opens canonical Hybrid Restaurant Detail rather than a second minimal confirm page;
- actual save/record actions remain existing Native services through typed handoff.

Evidence:

- `screenshots/batch-01/browser-mobile-add-restaurant-final.png`
- `screenshots/batch-01/add-search.png`
- `screenshots/batch-01/add-nearby.png`
- `screenshots/batch-01/add-share.png`
- `screenshots/batch-01/add-manual.png`

Gates: UI FUNCTION **PASS** · BROWSER ↔ CAPACITOR VISUAL PARITY **PASS** · LAFAYETTE/FORMAL REFERENCE PARITY **PASS**.

### 3. Restaurant Detail and Visit edit integration

- all Browser/Hybrid entry points use one `RestaurantPreviewCard` canonical body;
- public/cached Restaurant references stay readable without granting edit/delete rights;
- capabilities are explicit Native DTO fields;
- current-user Visit history shows exactly one lightweight Edit entry per editable Visit;
- Edit opens existing Native `VisitEditorView`;
- save returns to the same Hybrid Restaurant Detail and automatically refetches the summary;
- Add/Nearby candidates enter this same canonical detail.

Gates: Product Contract **PASS** · Ownership **PASS** · Return/refresh **PASS** · second Detail implementation **absent**.

### 4. Lists

- shared Browser/Capacitor React renderer;
- My Lists and Public Lists retained;
- visibility, images and Restaurant navigation retained;
- Native write/manage capabilities remain typed handoffs rather than fake React writes.

Evidence: `screenshots/batch-01/lists-*.png`.

Gates: UI FUNCTION **PASS** · cross-platform parity **PASS** · current capability preservation **PASS**.

### 5. Roulette

- shared approved wheel renderer;
- real Restaurant imagery, names, ratings and cities retained;
- candidate state is preserved across Hybrid routes;
- exact formal title `今天吃什么` restored;
- selected Restaurant opens canonical Detail.

Evidence: `screenshots/batch-01/roulette-*.png`.

Gates: UI FUNCTION **PASS** · cross-platform parity **PASS** · approved visual family **PASS**.

### 6. Analytics and Posters

- five modes retained: `我的口味档案 / 最佳饭搭子 / 谁最会种草 / 本月回顾 / 年度回顾`;
- shared high-fidelity editorial/infographic family, not a generic settings dashboard;
- Restaurant image priority remains real-photo-first;
- representative Restaurant navigation remains canonical;
- five 9:16 poster renderers use the same formal `renderAnalysisPosterBlob` pipeline;
- Native uses the system share handoff; Browser exports a real poster blob.

Evidence:

- `screenshots/batch-01/analytics-*.png`
- `screenshots/batch-01/poster-*.png`

Gates: UI FUNCTION **PASS** · BROWSER ↔ CAPACITOR **PASS** · LAFAYETTE analysis/poster reference **PASS**.

### 7. Premium

- approved historical hamburger badge retained;
- Free, Premium Active and StoreKit unavailable states retained;
- no fake price, Product ID, transaction or purchase success;
- purchase/restore UI remains visible and hands off to the formal StoreKit/native capability.

Evidence: `screenshots/batch-01/premium-active.png`.

Gates: UI FUNCTION **PASS** · entitlement semantics **PASS** · Release fail-closed **PASS**.

### 8. Settings

- formal sections: Account, Data & Backup, Sync, Privacy & Permissions, Storage & Premium, Help & About;
- current Sync status and account/data capabilities retained;
- Backup v1 privacy text retained;
- high-risk tools remain existing Native services via typed handoff;
- retired Google Drive controls removed from the legacy Browser modal without deleting provider abstractions or historical data compatibility;
- no fake legal, delete-account or production capability introduced.

Evidence: `screenshots/batch-01/settings-main.png`.

Gates: UI FUNCTION **PASS** · current capability preservation **PASS** · negative retired-feature contract **PASS**.

## Global shell closure

- route registry and UI navigation are independent;
- bottom navigation is exactly `地图 / 发现 / 我的`;
- Add Restaurant is a route, never a fourth tab;
- the single Add primary CTA belongs to Map;
- Map/List/filters share one state;
- no numeric/food-count clusters or default marker dispersion;
- Browser and Capacitor equality is not used as a substitute for Product correctness.

## Tests and builds

| Verification | Result |
| --- | --- |
| TypeScript/Worker full Vitest | PASS — 56 files / 386 tests |
| Exact/negative Hybrid Product Contract | PASS — 4 files / 32 tests |
| Hybrid route/platform + Swift package | PASS — 12 TS + 6 Swift |
| iOS full unit/integration | PASS — 65 suites / 638 tests |
| Key Hybrid UI E2E | PASS — shared Discovery, global nav, rich primary routes, Visit edit/refresh |
| TypeScript typecheck | PASS |
| Changed-source ESLint | PASS — 0 errors; one pre-existing hook dependency warning in `CommunityPage` |
| Browser Vite production build | PASS |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| generic iOS device Release compile | PASS |
| Formal Release purity scan | PASS — 36 App files / 16 signed Web files |

Repository-wide `pnpm lint` still scans generated `build/` Capacitor framework JavaScript and existing unrelated legacy test/Worker lint debt; those baseline errors were not changed or hidden. The complete set of changed TypeScript/React sources was linted separately with zero errors.

## Release purity

The repository is staged with the formal `vite-hybrid-release` bundle. `_hybrid_debug`, Rich Demo fixtures, test auth, UI-test runtime, Development API URL, local developer paths, private-key markers and credential fields are absent from the formal Release App and signed React bundle.

The fixed Simulator remains booted with the installed Debug Rich Demo build for Lafayette inspection. Restaging the repository to formal Release does not change the already installed Debug app.

## Screenshot index

- Capacitor latest Map: `screenshots/batch-01/capacitor-map-launch-final.png`
- Browser mobile Discovery: `screenshots/batch-01/browser-mobile-discovery-final.png`
- Browser mobile Add Restaurant: `screenshots/batch-01/browser-mobile-add-restaurant-final.png`
- Discovery/Community: `screenshots/batch-01/discovery-*.png`
- Add/Nearby states: `screenshots/batch-01/add-*.png`
- Lists: `screenshots/batch-01/lists-*.png`
- Roulette: `screenshots/batch-01/roulette-*.png`
- Analytics: `screenshots/batch-01/analytics-*.png`
- Posters: `screenshots/batch-01/poster-*.png`
- Premium: `screenshots/batch-01/premium-active.png`
- Settings: `screenshots/batch-01/settings-main.png`

## Final acceptance

| Gate | Result |
| --- | --- |
| PRODUCT CONTRACT | PASS |
| ONE REACT UI | PASS |
| CURRENT CAPABILITY PRESERVATION | PASS |
| BROWSER ↔ CAPACITOR | PASS |
| REFERENCE PARITY | PASS for applicable surfaces; N/A where no controlling reference exists |
| FUNCTION / SEMANTIC | PASS |
| NEGATIVE CONTRACT | PASS |

Batch 1 may be closed. Batch 2 has not started.
