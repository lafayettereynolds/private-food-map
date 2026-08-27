# P2-C Dish recording

## Domain semantics

P2-C keeps the single P2-A `Dish` entity and makes its intended scope explicit:

- `Dish` is a Restaurant-level canonical dish record.
- `Dish.restaurantId` owns the dish.
- `Dish.visitId` is retained as the immutable origin/legacy Visit required by the P2-A and Web V1 contract.
- Current Visit membership is represented by `VisitDish`; one Dish may be associated with many Visits.
- `Dish.rating`, `Dish.price`, and `Dish.taste` remain canonical dish fields because the existing Web/P2-A model has no Visit-specific observation entity. Editing them updates the shared Dish.
- Removing a Dish from a Visit tombstones/deletes only `VisitDish`. It does not delete the Restaurant Dish.

This is a compatibility bridge. If a future product requirement needs “this Visit was saltier” or a per-Visit dish rating, add explicit nullable fields to `VisitDish` in a new contract version instead of overloading the canonical Dish.

## Identity and duplicate protection

The client normalizes a name by trimming, collapsing whitespace, and applying case, diacritic, and width folding with a stable POSIX locale. A new Dish ID is derived from:

`SHA256(Restaurant remote ID + normalized dish name)`

The UI and local store reuse the earliest canonical active Dish with the same normalized name under the same Restaurant. This handles obvious spacing/case/width duplicates without attempting semantic or AI name merging. Existing legacy duplicates are not destructively merged; Restaurant Detail groups them for presentation while preserving their original IDs and associations.

Renaming a Dish to an existing normalized name reuses that existing canonical Dish for the current Visit instead of creating another duplicate. A Dish remote ID remains stable after rename. If a later new Dish reuses the retired old name, the deterministic name-derived ID is already reserved, so the client assigns a fresh stable UUID-based Dish ID rather than violating identity uniqueness.

The origin association uses `legacy:<dishId>:<visitId>` so old P2-A Dish pushes and new P2-C explicit association pushes converge on the same record. Later Visit associations use a deterministic hash of Visit ID and Dish ID. D1 additionally enforces `UNIQUE(user_id, visit_id, dish_id)`.

## Shared JSON contract

`VisitDishJSONContractV1` / `VisitDishSyncContractV1` has these required fields:

- `schemaVersion`
- `id`
- `userId` (informational only; Worker authentication is authoritative)
- `restaurantId`
- `visitId`
- `dishId`
- `sortOrder`
- `createdAt`
- `updatedAt`
- `deletedAt`

`deletedAt` is required and nullable. IDs must be non-empty, order must be non-negative, timestamps must be ISO-8601, and unknown fields are rejected by both TypeScript and Swift decoders. Pull decoding remains backward-compatible when an older response omits the top-level `visitDishes` array.

## Offline and sync behavior

Visit editing reconciles drafts locally first:

1. Restaurant and Visit exist locally.
2. A canonical Dish is reused or created.
3. A `VisitDish` association is created/re-enabled or removed.
4. SwiftData saves immediately and mutation state survives restart.
5. Sync pushes in dependency order: Restaurant → Visit → Dish → VisitDish → Photo.

Server mutation receipts make retries idempotent. The Worker recognizes a P2-A-generated origin association as semantically equivalent to the explicit P2-C mutation and records an applied receipt without creating a second row. Association deletion is a tombstone; a stale pre-delete version conflicts and cannot revive it. Explicit re-adding is only allowed from the current server version.

All server reads, parent checks, uniqueness, and writes use the authenticated Taste Map user ID. Payload `userId` never grants ownership.

## Migration 0020

`0020_visit_dish_associations.sql` is additive. It:

- creates `visit_dishes` and indexes;
- maps every existing Dish to its original Visit with a deterministic compatibility ID;
- preserves existing Restaurant, Visit, Dish, Photo, and Web JSON data;
- creates V3 sync change/receipt ledgers so `visitDish` is a versioned entity;
- copies all V2 revisions without changing their revision numbers, preserving existing cursors;
- adds bootstrap VisitDish changes after the previous maximum cursor.

The migration must only be applied through normal Wrangler migration tracking. It must not be rerun manually, used to reset a database, or applied to Production as part of P2-C development verification.

## UI behavior

Visit Editor provides “本次吃了什么” with:

- existing Dish search and direct selection;
- new Dish form with required name, optional half-star rating, nullable non-negative Decimal price, and multiline “口味与备注” (`taste`);
- optional relationship to an existing P2-B PhotoAsset without copying binary data;
- explicit edit and “remove from this Visit” controls.

Restaurant Detail presents grouped dishes by frequency, then latest Visit, then name. It shows name, canonical rating/price, visit count, latest date, optional thumbnail, note, and the Visits where the dish appeared. Dish rating does not affect Restaurant/Visit rating, and Dish prices never recalculate `myActualSpend`.
