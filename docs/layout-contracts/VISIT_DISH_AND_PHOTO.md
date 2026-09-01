# Visit, Dish, and Photo Layout Contract

## Visit editor

Restaurant context is fixed; every other field is optional and the Save action
remains available. The page groups, in product order:

1. Restaurant identity and visit date.
2. Optional overall rating with an explicit `未评分` state.
3. Optional detailed ratings.
4. Optional note.
5. Optional actual personal spend.
6. Optional dishes and photos.
7. Optional dining context, companions, and recommendation source.
8. Visibility and destructive actions when editing.

Fields use shared section headers, compact selectors, and native editing
controls. Optional means visually optional; no placeholder suggests a value was
recorded when it was not.

## Dishes and photos

- Dish rows group name, rating/note, and associated media without competing
  with the Restaurant identity.
- Photo selection, local state, upload state, retry, delete, and missing binary
  are distinct. Visit save never waits for upload.
- Real user media is never replaced by decorative Food/Dining art.
- Empty Dish/Photo states use the canonical empty-state system.

## Retired fields

Do not restore willingness-to-return, recommended/avoid dishes, seating,
reservation beyond queue, or best-visit-time fields.

## States

Create/edit, rated/unrated, partial detailed rating, spend missing/present,
photo pending/uploading/failed/synced/missing, dish empty/rich, offline, long
note, keyboard, Dynamic Type, and deletion confirmation.
