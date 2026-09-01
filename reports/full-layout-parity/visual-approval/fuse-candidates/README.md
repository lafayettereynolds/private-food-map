# Taste Map FUSE V1 Candidate Manifest

These screenshots are visual approval candidates, not approved product UI.

- Candidate branch: `preview/fuse-visual-candidates`
- Candidate worktree: `/Users/lafayette/Projects/private-food-map-fuse-visual-candidates`
- Baseline commit: `39a3c9307aea501657ec7b8f56d79cc4ce3aaf7b`
- Build: `TasteMap` Debug Simulator build succeeded
- Device: the existing booted `iPhone 17 Pro` Simulator (`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`)
- Capture resolution: `1206 × 2622`
- Implementation: DEBUG-only SwiftUI candidate route in the isolated worktree
- Formal product branch modified by candidate SwiftUI: **NO**
- Production accessed or modified: **NO**

No screenshot is an AI mockup, Photoshop composite, HTML mockup, relabeled Current screenshot, or relabeled Legacy screenshot.

| Approval area | Real FUSE screenshot(s) | Legacy base used | Current capabilities preserved |
| --- | --- | --- | --- |
| Profile | `fuse-v1-profile-real-implementation.png` | Compact Legacy Dashboard topology, horizontal relationships/statistics, grouped entries | Premium, followers/following, visited/want/spend, Roulette, five analysis entries, Lists, Social, Sharing, Settings |
| Visit Editor | `fuse-v1-visit-editor-real-implementation.png` | Single-meal diary sequence and compact grouped form | Nil semantics, multidimensional ratings, spending, companions, recommendation sources, Dish/Photo, local-first save |
| Dish / Photo | `fuse-v1-dish-photo-real-implementation.png` | Dish and photography as one Visit story | Local originals, cloud copy, upload/retry states, independent Dish/Photo records and safe deletion boundaries |
| Public Profile / Social | `fuse-v1-public-profile-real-implementation.png` | Public identity → relationship → Restaurant/activity/list evidence | Follow, sharing, shared-meal action, report/block, public lists and server-backed social semantics |
| Lists / Public Lists | `fuse-v1-lists-real-implementation.png` | Collection/ranked hierarchy, cover, visibility and dense rank order | Canonical real Restaurant imagery, sync/ownership, sharing, visibility and stable membership |
| Analytics × 4 | `fuse-v1-analytics-companion-real-implementation.png`, `fuse-v1-analytics-source-real-implementation.png`, `fuse-v1-analytics-monthly-real-implementation.png`, `fuse-v1-analytics-annual-real-implementation.png` | Approved central Food Hero family, surrounding callouts, editorial whitespace and real Restaurant evidence | Current analyzers, owner scope, data sufficiency, official naming, consumption/time/trajectory data and poster entry |
| Share posters × 5 | `fuse-v1-poster-taste-real-implementation.png`, `fuse-v1-poster-companion-real-implementation.png`, `fuse-v1-poster-source-real-implementation.png`, `fuse-v1-poster-monthly-real-implementation.png`, `fuse-v1-poster-annual-real-implementation.png` | Dedicated social-poster composition rather than page screenshots | Native 9:16 renderer, Food Hero, true Restaurant imagery, privacy-safe brand footer, Share/Save lifecycle |
| Premium Paywall | `fuse-v1-paywall-real-implementation.png` | Approved historical hamburger and clear benefit hierarchy | StoreKit/server entitlement truth, restore, transaction lifecycle and fail-closed product facts |
| Settings / Data | `fuse-v1-settings-real-implementation.png` | Grouped Account/Data tools and high scanability | Account, Backup/Import, Sync, Privacy, Permissions, Storage, Premium, Help, About and legal gating |

## Region-level convergence rule

The page-level approval choices are:

- `Current`
- `Legacy｜Use Legacy Layout as Base`
- `FUSE｜Legacy + Current Structural Fusion`
- `Option A`
- `Option B`
- `Needs redesign`

`Legacy` means the historical page's overall layout, composition, and information architecture are already the correct visual base. Current-only approved capabilities are embedded with minimum structural intrusion. It does **not** authorize code rollback, removal of Current features, restoration of old data architecture, or restoration of retired fields.

`FUSE` means neither full page is used as-is: selected Legacy and Current structures are deliberately recomposed into a new candidate. Therefore `Legacy` and `FUSE` are separate approval decisions.

### Region-level convergence

The approval tool stores one decision per principal region:

- `KEEP CURRENT`
- `KEEP LEGACY`
- `KEEP FUSE`
- `CHANGE`
- `NEEDS REDESIGN`

A `KEEP` choice immediately freezes that region. The UI disables further choices until Lafayette explicitly selects **解除冻结后再修改**. A page is shown as `APPROVED FINAL` only when every required region has a frozen `KEEP` decision. Exported approval summaries include the region choice, source, frozen state, and Lafayette notes so a future FUSE V2/V3 can modify only open regions.
