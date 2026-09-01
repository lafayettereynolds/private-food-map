# Taste Map Final Screenshot Atlas

Task C evidence captured from the fixed iPhone 17 Pro / iOS 26.5 Simulator
(`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`). These files are implementation
evidence at the Task C commit. They are **CANDIDATE_CANONICAL** only; none is
promoted to `APPROVED_CANONICAL` without Lafayette's explicit confirmation.

The atlas contains **76 kept screenshots**. The tables below point to the
representative image for every required family; adjacent states and regression
evidence remain in this directory under deterministic names.

## Global shell and states

| State | Evidence |
| --- | --- |
| Root tabs / top controls | [`task-04-map-after.png`](task-04-map-after.png) |
| Compact filter sheet | [`final-atlas-map-filter-sheet.png`](final-atlas-map-filter-sheet.png) |
| Canonical empty state | [`full-layout-closure-canonical-empty-state.png`](full-layout-closure-canonical-empty-state.png) |
| Recoverable error | [`final-atlas-visual-qa-discovery-error.png`](final-atlas-visual-qa-discovery-error.png) |
| Offline state | [`p3-d-community-offline-cache.png`](p3-d-community-offline-cache.png) |
| Actual Dark appearance | [`core-parity-discovery-dark.png`](core-parity-discovery-dark.png) |
| Actual Accessibility Extra Extra Large | [`task09-rich-map-accessibility.png`](task09-rich-map-accessibility.png) |
| Final fixed-Simulator handoff: Rich + Premium | [`final-fixed-simulator-rich-premium.png`](final-fixed-simulator-rich-premium.png) |

## My Map and My List

| State | Evidence |
| --- | --- |
| Visited / standard Map | [`task-04-map-after.png`](task-04-map-after.png) |
| Rich Map / real images | [`legacy-fusion-02-map-real-restaurant-images.png`](legacy-fusion-02-map-real-restaurant-images.png) |
| Honest no-photo fallback | [`legacy-fusion-02-map-honest-fallback.png`](legacy-fusion-02-map-honest-fallback.png) |
| Dense natural overlap / selected z-order | [`legacy-fusion-rich-natural-markers.png`](legacy-fusion-rich-natural-markers.png) |
| My List | [`task-04-list-after.png`](task-04-list-after.png) |
| My List / canonical images | [`legacy-fusion-02-my-list-images.png`](legacy-fusion-02-my-list-images.png) |
| Missing-photo List | [`final-atlas-visual-qa-missing-photo-list.png`](final-atlas-visual-qa-missing-photo-list.png) |
| Map Dark | [`task-04-map-dark-after.png`](task-04-map-dark-after.png) |

Want-to-go and Recommended use the same title/scope/filter/query template and
are covered behaviorally in the Map/List UI suite. Their state preservation is
not represented as a second invented page template.

## Discovery and Community

| State | Evidence |
| --- | --- |
| Following / Community | [`p3-d-community-feed.png`](p3-d-community-feed.png) |
| For You | [`final-atlas-discovery-for-you.png`](final-atlas-discovery-for-you.png) |
| Same Taste | [`task-02-same-taste-content-after.png`](task-02-same-taste-content-after.png) |
| Latest | [`final-atlas-discovery-latest.png`](final-atlas-discovery-latest.png) |
| Trending | [`final-atlas-discovery-trending.png`](final-atlas-discovery-trending.png) |
| Real Restaurant imagery | [`legacy-fusion-02-discovery-images.png`](legacy-fusion-02-discovery-images.png) |
| Offline cache | [`p3-d-community-offline-cache.png`](p3-d-community-offline-cache.png) |
| Error / Retry | [`final-atlas-visual-qa-discovery-error.png`](final-atlas-visual-qa-discovery-error.png) |
| Dark | [`core-parity-discovery-dark.png`](core-parity-discovery-dark.png) |
| Accessibility Extra Extra Large | [`task09-rich-discovery-accessibility.png`](task09-rich-discovery-accessibility.png) |

Loading remains a transient ProgressView state verified by the state contract;
it is deliberately not frozen as a canonical still because timing-only captures
are nondeterministic.

## Add Restaurant

| Flow | Evidence |
| --- | --- |
| Search result preview | [`product-ux-restaurant-search-preview.png`](product-ux-restaurant-search-preview.png) |
| Nearby | [`full-parity-add-restaurant-nearby-after.png`](full-parity-add-restaurant-nearby-after.png) |
| Provider candidate | [`product-ux-restaurant-candidate-preview.png`](product-ux-restaurant-candidate-preview.png) |
| Shared URL/text recognition | [`product-ux-external-share-recognition.png`](product-ux-external-share-recognition.png) |
| Shared URL/text preview | [`product-ux-external-share-preview.png`](product-ux-external-share-preview.png) |
| Manual form | [`product-ux-manual-restaurant.png`](product-ux-manual-restaurant.png) |
| Manual confirmation preview | [`product-ux-manual-restaurant-preview.png`](product-ux-manual-restaurant-preview.png) |

## Canonical Restaurant Detail

| State | Evidence |
| --- | --- |
| Top / local entry | [`task-04-restaurant-detail-after.png`](task-04-restaurant-detail-after.png) |
| Canonical real image | [`legacy-fusion-02-restaurant-detail-image.png`](legacy-fusion-02-restaurant-detail-image.png) |
| Local downstream sections | [`global-restaurant-detail-local-after.png`](global-restaurant-detail-local-after.png) |
| Remote/community downstream sections | [`global-restaurant-detail-remote-after.png`](global-restaurant-detail-remote-after.png) |

The local and remote paths assert the same `RestaurantDetailStandardBody`,
including rating reference, photos, personal overview, and visit history.

## Visit, Dish, and Photo

| State | Evidence |
| --- | --- |
| Optional core form | [`final-atlas-visit-core-form.png`](final-atlas-visit-core-form.png) |
| Photos, dishes, companions/source and context | [`final-atlas-visit-rich-photo-dish-context.png`](final-atlas-visit-rich-photo-dish-context.png) |
| Detailed partial ratings | [`final-atlas-visit-detailed-ratings.png`](final-atlas-visit-detailed-ratings.png) |

## Profile, public profile, Lists, and On This Day

| State | Evidence |
| --- | --- |
| Premium dashboard | [`final-atlas-profile-premium-analytics.png`](final-atlas-profile-premium-analytics.png) |
| Free dashboard | [`final-atlas-profile-free.png`](final-atlas-profile-free.png) |
| Empty profile | [`final-atlas-visual-qa-empty-profile.png`](final-atlas-visual-qa-empty-profile.png) |
| Long text profile | [`final-atlas-visual-qa-long-text-profile.png`](final-atlas-visual-qa-long-text-profile.png) |
| Public profile | [`core-parity-public-profile-after.png`](core-parity-public-profile-after.png) |
| Own/public ranked List | [`p4-f-own-public-ranking.png`](p4-f-own-public-ranking.png) |
| Public List action | [`p4-f-public-list-to-want-to-go.png`](p4-f-public-list-to-want-to-go.png) |
| On This Day | [`f7-a-on-this-day.png`](f7-a-on-this-day.png) |
| Profile Dark | [`core-parity-profile-dark.png`](core-parity-profile-dark.png) |
| Profile Accessibility Extra Extra Large | [`task09-rich-profile-premium.png`](task09-rich-profile-premium.png) |

## Roulette

| State | Evidence |
| --- | --- |
| Full ten candidates / approved wheel | [`p4-g-large-candidate-pool.png`](p4-g-large-candidate-pool.png) |
| Real Restaurant imagery | [`legacy-fusion-02-roulette-images.png`](legacy-fusion-02-roulette-images.png) |
| Result | [`p4-g-roulette-result.png`](p4-g-roulette-result.png) |
| Candidate manager → official manual add | [`p4-g-candidate-manager-to-manual-add.png`](p4-g-candidate-manager-to-manual-add.png) |
| Empty | [`full-layout-closure-canonical-empty-state.png`](full-layout-closure-canonical-empty-state.png) |
| Actual Dark | [`final-atlas-roulette-dark.png`](final-atlas-roulette-dark.png) |
| Actual Accessibility Extra Extra Large | [`final-atlas-roulette-large-text.png`](final-atlas-roulette-large-text.png) |

## Analytics and five independent posters

| Family | In-app analysis | Independent 9:16 poster |
| --- | --- | --- |
| My Taste Profile | [`p4-a-taste-profile.png`](p4-a-taste-profile.png) | [`p4-a-9x16-poster.png`](p4-a-9x16-poster.png) |
| Best Companion | [`p4-b-companion-detail.png`](p4-b-companion-detail.png) | [`p4-b-9x16-poster.png`](p4-b-9x16-poster.png) |
| Who Recommends Best | [`p4-c-recommendation-source-overview.png`](p4-c-recommendation-source-overview.png) | [`p4-c-9x16-poster.png`](p4-c-9x16-poster.png) |
| Monthly Recap | [`p4-d-monthly-recap-current.png`](p4-d-monthly-recap-current.png) | [`p4-d-9x16-monthly-poster.png`](p4-d-9x16-monthly-poster.png) |
| Annual Recap | [`p4-e-annual-recap-current.png`](p4-e-annual-recap-current.png) | [`p4-e-9x16-annual-poster.png`](p4-e-9x16-annual-poster.png) |

Previous-period evidence is retained as
[`p4-d-monthly-recap-previous.png`](p4-d-monthly-recap-previous.png) and
[`p4-e-annual-recap-previous.png`](p4-e-annual-recap-previous.png). Canonical
Restaurant imagery in analysis is shown in
[`legacy-fusion-02-analytics-restaurant-images.png`](legacy-fusion-02-analytics-restaurant-images.png).

## Premium, Settings, Backup, Import, and Sync

| State | Evidence |
| --- | --- |
| Approved Premium identity asset | [`core-parity-approved-premium-hamburger.png`](core-parity-approved-premium-hamburger.png) |
| Free Paywall | [`p4-h-free-paywall.png`](p4-h-free-paywall.png) |
| Settings root | [`final-atlas-settings-root.png`](final-atlas-settings-root.png) |
| Backup privacy warning | [`final-atlas-backup-export-privacy.png`](final-atlas-backup-export-privacy.png) |
| Import preflight | [`final-atlas-import-preflight.png`](final-atlas-import-preflight.png) |
| Import blocking error | [`final-atlas-import-blocking-error.png`](final-atlas-import-blocking-error.png) |
| Import plan | [`final-atlas-import-plan.png`](final-atlas-import-plan.png) |
| Sync pending | [`final-atlas-sync-pending.png`](final-atlas-sync-pending.png) |
| Permissions | [`final-atlas-permissions.png`](final-atlas-permissions.png) |
| About | [`final-atlas-about.png`](final-atlas-about.png) |

## Acceptance boundary

- These screenshots prove the current implementation and deterministic state.
- They do not manufacture a missing Web reference.
- The nine unresolved visual choices are listed in
  [`../TASTEMAP_LAFAYETTE_VISUAL_APPROVAL_QUEUE.md`](../TASTEMAP_LAFAYETTE_VISUAL_APPROVAL_QUEUE.md).
- Physical GPS, share/save handoff, public-domain links, StoreKit, and real-device
  safe-area behavior remain external/device gates.
- Actual Accessibility Extra Extra Large captures expose truncation in compact
  high-density surfaces; that is recorded as an objective follow-up, not hidden
  behind an automated PASS.
