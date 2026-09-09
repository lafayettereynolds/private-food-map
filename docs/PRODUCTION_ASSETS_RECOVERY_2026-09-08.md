# Production Assets recovery — 2026-09-08 follow-up

SUPERSEDED DECISION: Lafayette selected ede1474e as the retained candidate; do not restore 29c76424. Its source has now been reproduced exactly from a39cdaa. The following section records historical recovery work, not an outstanding request for a decision/build path. See [candidate audit and actual live successor](../reports/PRODUCTION_BASELINE_AUDIT_2026-09-08.md).

## Deployment conflict discovered before any write

The requested baseline is `29c76424-037c-418d-b607-7a3d07ed6f1d` (2026-08-31 05:52:29 UTC). At the start of this follow-up the actual live deployment was already `ede1474e-cbaa-4e98-b75c-413af8ccc427` (2026-09-08 01:54:10 UTC), deployment `896d7767-f0ac-4152-95ea-63e012d05e7d`.

The newer deployment changed frontend assets, Worker code, routing, and added Monthly/Annual product configuration variables. No Cloudflare write, deploy, rollback, DB migration, R2 mutation, or iOS change was performed in this follow-up. Replacing this newer deployment is a separate decision; it cannot be treated as an unchanged old baseline.

## Search and historical reconstruction

- Inspected all 20 existing Git worktrees and all branches' 2026-08-30/31 history.
- Searched Taste Map build/index/log/archive/bundle candidates under Projects, Desktop, Documents, Downloads, `.codex/worktrees`, `/tmp`, Xcode Archives, and Wrangler logs/metadata. Excluded dependency internals and unrelated private inventories.
- Found Desktop `TasteMap-Git-Backup` bundles and inspected `product-ux-20260831-1548.bundle` (HEAD `5b9c861a2d3700fba20038f05ad9135e7bb1b0b7`); no committed dist in that tree.
- Candidate last pre-deployment main commit: `7e67c65258e1b4db9ee2ab45def242b072b0c1f6`; also inspected neighboring commit history including `a4739f0`, `11c7e2e`, `f9e8f5b`, `d9f5acd`, `facdbe4`, `ad83c7d`.
- Created independent detached worktree `/tmp/tastemap-production-recovery.PXmKfO/source` at `7e67c65`; installed frozen `pnpm-lock.yaml` (no new dependency resolution), then ran the historical `pnpm run build` (typecheck + Vite 6.4.3).
- Build succeeded but emitted `index-eQq1UUQg.js` and `index-BTZY7AYK.css`, not the old live `index-LapMPPNB.js` and `index-i0SELG91.css`. This candidate is NOT exact historical Web build parity and must not be deployed as such.
- Retrieved actual version-specific Worker modules through the Cloudflare version API with `include=modules`, not the mutable latest-script endpoint. Original module SHA-256: `aff99612f1fe554128d22360de4903e9201c56f6a910038a4f618146ed0587b8`.
- Old version API reports no routable version URLs. Attempting its version-preview hostname timed out. The old JS pathname at the current custom domain returns SPA HTML, not the original JS. A version-override request did not recover the old index. No public/private user-data API was fetched for asset recovery.

## Current production assets successfully recovered and verified

Wrangler deployment log `wrangler-2026-09-08_01-53-44_002.log` identifies `.private/rc-worker-assets` as the newer deployment asset directory. It is separate from current dirty/latest dist.

Downloaded only these publicly served static paths from `https://origin-api.tastemap.cn`; compared each response byte-for-byte and SHA-256 against that directory. **28/28 files PASS**, including:

- `index.html` (881 bytes)
- `assets/index-DIfmPhId.js` (1,177,998 bytes)
- `assets/index-DXqlPWjd.css` (350,703 bytes)
- lazy `assets/HybridAppShell-TW4GAm3e.js` and `assets/HybridAppShell-BO1XQjTZ.css`
- lazy `assets/restaurantSearchLocation-DOhbVvf1.js`
- `manifest.webmanifest`
- all five icons, six food-hero images, food-library catalog and seven images, map marker, avatar preset image

Recovered package: `/tmp/tastemap-production-recovery.PXmKfO/current-public-assets`.
Full per-file status, content type, byte size, local SHA-256, remote SHA-256, and equality: `/tmp/tastemap-production-recovery.PXmKfO/current-assets-parity.json`.

This is exact parity for **ede1474e**, not **29c76424**. It contains Hybrid chunks and must not be relabeled as an old-production-compatible minimal patch. Historical exact old JS/CSS bytes remain unavailable from checks performed so far; no claim of exhaustive reconstruction of every historical commit is made.

## Current production regression evidence

- `GET /health`: HTTP/2 200, `content-type: application/json`, `cache-control: no-store`, body exactly `{"status":"ok"}`.
- `/`: HTTP 200 HTML, bytes equal the current deployment artifact.
- All 28 public static files: byte/hash parity PASS.
- Unauthenticated `/api/v1/sync/pull`: HTTP/2 401 JSON, `{"error":"A verified Taste Map session is required."}`.
- Current version assets configuration includes `/health` before `/api/*` with SPA fallback preserved; also contains `/ready`, `/invite/*`, AASA and admin paths from the newer deployment.
- D1 DB identifier and R2 bucket unchanged from the original baseline; monthly/annual plain-text configuration variables are new in the externally published version.

## Decision required

Health is already working, but current production no longer matches the baseline assumed in the request. Decide whether to retain the now-live version or explicitly replace its newer frontend/backend/catalog changes with the older baseline and a health-only patch. Do not roll back this other deployment automatically as if it were a failed deployment from this follow-up.
