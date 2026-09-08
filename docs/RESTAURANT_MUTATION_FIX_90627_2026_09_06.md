# Restaurant mutation follow-up — 906.27

User reported on the private iPhone app: restaurant save leaves Detail loading indefinitely, and deleted restaurants remain marked visited/on the Map.

## Findings and changes

- Native restaurant detail lookup can resolve a global/provider reference to an owner-scoped local Restaurant ID. The Shell discarded that successful result because it compared only returned ID to route ID. It now also tracks the exact request whose response was accepted. An unrelated prior response is never accepted for a new route.
- Detail reads use the existing bounded read helper; read failure no longer falls back to an obsolete owner preview. Existing detail template and navigation ownership are unchanged.
- Local restaurant deletion now publishes `restaurantDeleted` after the persistence transaction commits, including offline unsynced deletion. No sync completion or sheet-dismiss callback is required for invalidation.
- Mounted Map consumes `data.changed` directly, invalidates pending responses and cached snapshots, clears stale deleted markers and reloads without waiting for a parent dashboard rerender. Existing map camera rules are unchanged.
- The event reason is included in the typed platform contract. All local Restaurant deletion consumers use the same store-level notification, rather than a single screen-specific notification.

## Verification

- 62 focused tests passed across detail identity, snapshot refresh, remaining UI contract and platform contract suites.
- TypeScript check, formal staging and release local-resource scan passed.
- Browser runtime probe `hybrid/scripts/check-restaurant-mutation-refresh.mjs` passed: real HybridAppShell provider→owner response renders Detail; mounted MyMapBrowsePage drops the deleted record after a data event without a parent profile rerender.
- Signed DebugPrivatePreview and DebugQA builds 906.27 succeeded; all 18 resources match formal stage in each artifact.
- Deployment targets the user-selected iPhone 17 Pro Max only, updating both existing app IDs in place. No user restaurant was created/deleted as a diagnostic test.
- iPhone Mirroring remained unlock-required. Real-phone end-to-end save/delete acceptance is still pending; these tests must not be described as observing the user's actual database or proving that no additional synchronization issue exists.

## Design System Compliance

Core UI: existing error/loading components, no new scales. Food & Dining visuals: unchanged. Canonical templates: Detail and Map retained. No new duplicate renderer or default-SwiftUI visual introduced. Full physical-device visual acceptance and prior illustration-library integration remain open.
