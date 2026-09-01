# Taste Map Legacy Visual Reference Manifest

These screenshots were captured from the read-only Legacy Windows/Web project extracted from:

- Archive: `/Users/lafayette/Desktop/Taste-Map-完整项目备份-2026-09-01.zip`
- Legacy commit: `fb127e9ea20498c0db450872deb9c9dc346ef34f`
- Browser viewport: `1280 × 720` at device scale factor `1`
- Capture environment: isolated local Vite/Worker/D1 preview; no Production service was accessed or modified

Every image in this directory is a browser capture of the running Legacy implementation. None is an AI mockup, composited approximation, or Current iOS screenshot relabeled as Legacy.

| Approval area | Screenshot | Legacy route/state | Evidence note |
| --- | --- | --- | --- |
| Profile header/dashboard | `legacy-fb127e9-profile-dashboard-1280x720.png` | `/` → My/Profile | Real logged-in dashboard topology and section grouping. |
| Visit Editor | `legacy-fb127e9-visit-editor-1280x720.png` | `/` → Restaurant → record repeat visit | Real editor header and upper form density. |
| Dish / Photo manager | `legacy-fb127e9-visit-dish-photo-manager-1280x720.png` | Same Visit Editor, lower section | Real historical manager state. The captured fixture did not create a quick-add dish; the screenshot intentionally records that historical runtime state rather than inventing content. |
| Public Profile / Social hub | `legacy-fb127e9-public-profile-social-1280x720.png` | `/` → local user search → `TestUser04` | Real public profile rendered against isolated local Worker/D1 fixtures. |
| Lists / Public Lists | `legacy-fb127e9-lists-public-list-1280x720.png` | `/` → Profile → Lists → public ranked list | Real list UI. The list and six fixture restaurants were created through the Legacy UI in the isolated local preview only. |
| My Taste Profile | `legacy-fb127e9-taste-profile-analysis-1280x720.png` | `/` → Profile → 我的口味档案 | Real analysis page. |
| Best Dining Companion | `legacy-fb127e9-companion-analysis-1280x720.png` | `/` → Profile → legacy dining companion analysis | Real analysis page; current user-visible naming is governed by the Current product rules. |
| Recommendation Source | `legacy-fb127e9-recommendation-source-analysis-1280x720.png` | `/` → Profile → legacy recommendation-source analysis | Real analysis page; current user-visible naming is governed by the Current product rules. |
| Monthly Review | `legacy-fb127e9-monthly-review-analysis-1280x720.png` | `/` → Profile → monthly review | Real empty state. Legacy fixture dates stop before September 2026, so no rich monthly result was fabricated. |
| Annual Review | `legacy-fb127e9-annual-review-analysis-1280x720.png` | `/` → Profile → annual review | Real rich annual analysis page. |
| Taste Profile poster | `legacy-fb127e9-taste-profile-poster-1280x720.png` | Taste Profile → Share | Real historical poster renderer output shown in the Legacy UI. |
| Companion poster | `legacy-fb127e9-companion-poster-1280x720.png` | Companion analysis → Share | Real historical poster renderer output shown in the Legacy UI. |
| Recommendation-source poster | `legacy-fb127e9-recommendation-source-poster-1280x720.png` | Recommendation-source analysis → Share | Real historical poster renderer output shown in the Legacy UI. |
| Monthly poster | `legacy-fb127e9-monthly-review-poster-1280x720.png` | Monthly review → Share | Real empty-state poster corresponding to the historical fixture date range. |
| Annual poster | `legacy-fb127e9-annual-review-poster-1280x720.png` | Annual review → Share | Real historical poster renderer output shown in the Legacy UI. |
| Premium Paywall | `legacy-fb127e9-premium-paywall-1280x720.png` | `/?testAccount=free` → Premium gate | Real paywall from the Legacy free-user state. The currently approved hamburger asset remains a separate Current design requirement. |
| Settings / Data | `legacy-fb127e9-settings-data-1280x720.png` | `/?testAccount=free` → Settings | Real historical Settings/Data information architecture. |

## Coverage result

All nine Lafayette approval areas have a real Legacy counterpart at the specified commit. Some current capabilities inside those areas—such as the current StoreKit entitlement architecture, expanded Social/Sharing behavior, modern sync diagnostics, and the five current native poster renderers—remain Current additions and must be preserved by any FUSE candidate.
