# Taste Map — Lafayette Visual Approval Queue

Date: 2026-09-01

This queue contains design choices that cannot be resolved from approved
references or active written rules. It intentionally excludes objective bugs,
test failures, external release configuration, and device-only verification.
All screenshots are `CANDIDATE_CANONICAL` until Lafayette explicitly approves a
version.

## 1. Profile compact identity density

- **Page:** My Profile / logged-in header.
- **Current screenshot:** [`final-atlas/final-atlas-profile-premium-analytics.png`](final-atlas/final-atlas-profile-premium-analytics.png), [`final-atlas/final-atlas-visual-qa-long-text-profile.png`](final-atlas/final-atlas-visual-qa-long-text-profile.png).
- **Reference(s):** [`../../reports/full-product-parity-assets/web-profile-before.jpg`](../full-product-parity-assets/web-profile-before.jpg) plus the current Profile contract.
- **Exact ambiguity:** the historical Web header is denser, but it predates current followers/following, Premium badge, sharing, city, join date, and the approved `去过 / 想去 / 总消费` strip.
- **Option A:** keep the current two-tier identity card and metric strip.
- **Option B:** reduce identity-card vertical padding and compress metadata/actions while retaining every current-only datum.
- **Codex recommendation:** **Option B**, provided the long-name and Dynamic Type variants are rechecked afterward.
- **Current-only capability impact:** none if the change is geometric only; Social, Premium, sharing, and current statistics must remain.

## 2. Visit editor final composition

- **Page:** Add/Edit Visit.
- **Current screenshot:** [`final-atlas/final-atlas-visit-core-form.png`](final-atlas/final-atlas-visit-core-form.png), [`final-atlas/final-atlas-visit-rich-photo-dish-context.png`](final-atlas/final-atlas-visit-rich-photo-dish-context.png).
- **Reference(s):** [`../../docs/layout-contracts/VISIT_DISH_AND_PHOTO.md`](../../docs/layout-contracts/VISIT_DISH_AND_PHOTO.md); no approved pixel reference exists.
- **Exact ambiguity:** whether the complete optional record should remain grouped as roomy sections or move toward a denser diary form.
- **Option A:** keep current grouped sections with explanatory copy.
- **Option B:** reduce inter-section space and helper-copy prominence while preserving every optional field and local-first save.
- **Codex recommendation:** **Option A** until a concrete reference is approved; its hierarchy makes optionality and nil semantics explicit.
- **Current-only capability impact:** Option B risks obscuring optional/nil behavior if compressed too far.

## 3. Dish and Photo manager composition

- **Page:** Visit media/dishes management.
- **Current screenshot:** [`final-atlas/final-atlas-visit-rich-photo-dish-context.png`](final-atlas/final-atlas-visit-rich-photo-dish-context.png).
- **Reference(s):** Visit/Dish/Photo written contract; no approved pixel reference.
- **Exact ambiguity:** inline diary composition versus separate manager-style groups for photo reuse, upload state, Dish editing, and deletion.
- **Option A:** retain the current manager-style grouped flow.
- **Option B:** make photos and dishes more visually editorial and inline within the Visit story.
- **Codex recommendation:** **Option A** because it exposes lifecycle and independent deletion safely; improve visual storytelling only after a reference is selected.
- **Current-only capability impact:** Option B must not hide upload state, local originals, retry, reuse, or independent Dish/Photo deletion.

## 4. Public Profile and social hub geometry

- **Page:** Public Profile / social discovery.
- **Current screenshot:** [`final-atlas/core-parity-public-profile-after.png`](final-atlas/core-parity-public-profile-after.png), [`final-atlas/p3-d-community-feed.png`](final-atlas/p3-d-community-feed.png).
- **Reference(s):** current written Profile/Social contract; Legacy has no equivalent complete capability.
- **Exact ambiguity:** compact public identity with embedded activity versus a more spacious identity-first profile.
- **Option A:** preserve the current compact public header and immediate activity/list evidence.
- **Option B:** increase identity prominence and move public evidence lower.
- **Codex recommendation:** **Option A** because public Restaurant/List navigation and relationship context remain visible without duplicating the private dashboard.
- **Current-only capability impact:** report, block, visibility, followers/following, lists, and public sharing must remain.

## 5. Lists and public Lists final density

- **Page:** Own ranked Lists and public List detail.
- **Current screenshot:** [`final-atlas/p4-f-own-public-ranking.png`](final-atlas/p4-f-own-public-ranking.png), [`final-atlas/p4-f-public-list-to-want-to-go.png`](final-atlas/p4-f-public-list-to-want-to-go.png).
- **Reference(s):** Lists written contract; no approved Web pixel reference.
- **Exact ambiguity:** data-dense ranking rows versus larger media-led Restaurant cards.
- **Option A:** keep current dense ranked rows and compact actions.
- **Option B:** enlarge Restaurant imagery and reduce simultaneous ranking metadata.
- **Codex recommendation:** **Option A**, because ranking order and membership management are the primary task; retain canonical images as supporting evidence.
- **Current-only capability impact:** public/private visibility, ordering, collaboration, sharing, and Want-to-Go actions must remain.

## 6. Four non-Taste-Profile analysis compositions

- **Page:** Best Companion, Who Recommends Best, Monthly Recap, Annual Recap.
- **Current screenshot:** [`final-atlas/p4-b-companion-detail.png`](final-atlas/p4-b-companion-detail.png), [`final-atlas/p4-c-recommendation-source-overview.png`](final-atlas/p4-c-recommendation-source-overview.png), [`final-atlas/p4-d-monthly-recap-current.png`](final-atlas/p4-d-monthly-recap-current.png), [`final-atlas/p4-e-annual-recap-current.png`](final-atlas/p4-e-annual-recap-current.png).
- **Reference(s):** [`final-atlas/p4-a-taste-profile.png`](final-atlas/p4-a-taste-profile.png) and the Analysis/Poster written contract; no separately approved pixel reference for the four pages.
- **Exact ambiguity:** how strictly every family should repeat Taste Profile's centered Hero/four-corner composition versus varying narrative modules around the same Analysis visual system.
- **Option A:** keep the current page-specific narratives under the shared warm-paper/Hero/callout/Restaurant-evidence language.
- **Option B:** normalize all four pages more tightly to the Taste Profile center-Hero composition.
- **Codex recommendation:** **Option A**; the data semantics differ enough to justify different scroll narratives, while posters provide the stronger shared family identity.
- **Current-only capability impact:** all analyzer evidence, sample sufficiency, period navigation, `最坑推荐来源`, trajectory, and real Restaurant evidence must remain.

## 7. Five share posters as final campaign art

- **Page:** five independent 9:16 poster previews.
- **Current screenshot:** [`final-atlas/p4-a-9x16-poster.png`](final-atlas/p4-a-9x16-poster.png), [`final-atlas/p4-b-9x16-poster.png`](final-atlas/p4-b-9x16-poster.png), [`final-atlas/p4-c-9x16-poster.png`](final-atlas/p4-c-9x16-poster.png), [`final-atlas/p4-d-9x16-monthly-poster.png`](final-atlas/p4-d-9x16-monthly-poster.png), [`final-atlas/p4-e-9x16-annual-poster.png`](final-atlas/p4-e-9x16-annual-poster.png).
- **Reference(s):** active Analysis/Poster contract and current Food & Dining visual rules; no Lafayette-approved final poster image.
- **Exact ambiguity:** restrained editorial warmth versus more assertive food-story decoration for social sharing.
- **Option A:** freeze the current restrained family as canonical.
- **Option B:** increase visual storytelling with additional receipt/tableware accents while retaining real data and legibility.
- **Codex recommendation:** **Option A** for V1; it is cohesive, readable, independently rendered, and avoids fabricated data semantics.
- **Current-only capability impact:** renderer, Share/Save, real image policy, brand footer, and fail-closed QR behavior must remain.

## 8. Premium Paywall geometry beyond the approved badge

- **Page:** Premium Paywall / Free state.
- **Current screenshot:** [`final-atlas/p4-h-free-paywall.png`](final-atlas/p4-h-free-paywall.png), [`final-atlas/core-parity-approved-premium-hamburger.png`](final-atlas/core-parity-approved-premium-hamburger.png).
- **Reference(s):** approved hamburger asset only; no approved full Paywall screenshot.
- **Exact ambiguity:** compact entitlement explanation versus more promotional benefit storytelling.
- **Option A:** keep current restrained capability-first Paywall.
- **Option B:** increase benefit hierarchy and hero prominence without fake price or product data.
- **Codex recommendation:** **Option A** until real StoreKit products/localization exist; product facts should drive final commerce geometry.
- **Current-only capability impact:** StoreKit loading, restore, entitlement states, configuration failure, and approved hamburger identity must remain.

## 9. Settings and Data utility geometry

- **Page:** Settings, Backup, Import, Sync, Permissions, About.
- **Current screenshot:** [`final-atlas/final-atlas-settings-root.png`](final-atlas/final-atlas-settings-root.png), [`final-atlas/final-atlas-backup-export-privacy.png`](final-atlas/final-atlas-backup-export-privacy.png), [`final-atlas/final-atlas-import-preflight.png`](final-atlas/final-atlas-import-preflight.png), [`final-atlas/final-atlas-sync-pending.png`](final-atlas/final-atlas-sync-pending.png).
- **Reference(s):** locked Settings/Data information architecture; no approved pixel reference.
- **Exact ambiguity:** current native utility density versus a more branded card system.
- **Option A:** keep the current native, highly readable utility hierarchy.
- **Option B:** increase Taste Map card styling and Food/Dining decoration.
- **Codex recommendation:** **Option A**. Settings is a utility surface; brand identity should not reduce scanning or imply data semantics.
- **Current-only capability impact:** Account, Backup/Import, Sync, permissions, storage, legal availability, and release-safe feature gating must remain.

## Objective follow-up excluded from this queue

Actual `accessibility-extra-extra-large` screenshots show loss of visible values
and truncation in high-density Profile/Discovery/Roulette chrome. This is not a
subjective Lafayette choice and is therefore **not** an approval item. It is an
objective accessibility layout follow-up documented in the final acceptance
report.
