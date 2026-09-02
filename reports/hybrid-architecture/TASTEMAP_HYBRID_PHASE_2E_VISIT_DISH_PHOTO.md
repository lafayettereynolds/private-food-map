# Taste Map Hybrid Phase 2E — Visit, Dish, and Photo

Date: 2026-09-03  
Branch: `feature/hybrid-remaining-ui-batch`  
Production owner: SwiftUI (`NATIVE_PRIMARY`)  
Migration status: Visit editor `HYBRID_INTEGRATED`, not `HYBRID_PRIMARY`

## Outcome

The shared Browser/Capacitor Visit Editor now owns one React UI for Visit and Dish input while native iOS owns photo selection, file processing, private storage, SwiftData relationships, upload queueing, retry, and deletion. The bridge transfers opaque identifiers and safe `tastemap-resource://` preview descriptors only.

No second JavaScript persistence, credential, file-path, photo-upload, or synchronization implementation was introduced.

## Architecture

```text
Shared AddVisitModal / DishEditor / VisitPhotoPicker
    -> TasteMapPlatform.photo + TasteMapPlatform.visit
    -> typed TasteMapNative.v1 envelopes
    -> TasteMapHybridRuntime
    -> existing PhotoImportService / PhotoTransferCoordinator
    -> existing LocalVisitRecordingStore / SwiftDataSyncQueue
    -> existing SwiftData / photo upload queue
```

Browser continues to use its existing browser file input and Web behavior. Capacitor uses `PHPickerViewController`; the shared components are not forked.

## Photo contract

- `photo.pick` accepts a bounded selection limit and returns opaque `photoID` values plus native-resource thumbnails.
- `photo.discard` removes only an owner-visible pending selection or owned photo.
- `photo.retry` reaches the existing upload retry path for the current owner only.
- Pending Visit and Dish attachments are expressed as `photoID` plus an optional Dish draft ID.
- A Dish draft ID is resolved only after the existing Visit/Dish transaction creates the canonical Dish.
- Absolute file paths, base64 image bodies, Apple credentials, access tokens, and owner IDs never cross into React.
- Canceling a dirty Visit draft confirms abandonment and discards unsaved native selections.

## Failure boundary

Visit and Dish writes remain the primary transaction. A photo attachment/upload preparation failure does not roll back the successfully saved Visit or Dish graph. The result returns a bounded user-visible warning, local partial artifacts are removed, and successful photos remain queued through the existing idempotent transfer coordinator.

## Ownership and isolation

- The Runtime derives the owner from `NativeAuthServices.localAccountScope`; React cannot provide or override it.
- Pending selections are held in memory with their authenticated owner.
- Native preview loading checks pending/SwiftData photo ownership before returning bytes.
- Existing current-user Restaurant, Visit, Dish, PhotoAsset, mutation queue, and photo transfer services remain authoritative.
- No SwiftData schema, Worker, D1, R2, SyncEngine, Keychain, or Production configuration changed.

## Verification

| Gate | Result |
| --- | --- |
| TypeScript typecheck | PASS |
| Hybrid platform/route tests | PASS — 13 tests |
| Hybrid Swift package tests | PASS — 6 tests |
| Hybrid Phase 2A integration + P2-B photo tests | PASS — 15 tests |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Formal Release bundle scan | PASS — 38 app files, 16 signed Web files |
| Release Debug/fixture/Development URL/local path/secret scan | PASS |
| Credential surface in React | PASS — none |

## Remaining gates

- Lafayette visual acceptance of the shared Visit/Dish/Photo editor.
- Real-iPhone Photos picker, limited-library, permission, upload/retry, offline, and delete smoke.
- Explicit Lafayette approval before any `HYBRID_PRIMARY` switch.

This phase does not change the production owner and does not start Batch 3.
