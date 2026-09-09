# Homepage and footprint visibility linkage — 0811

Lafayette explicitly authorized historical24 Visits and their attached content to
follow Settings homepage visibility. Profile public/friends/private now synchronizes
legacy Visit/Photo fields through the existing owner-scoped mutation queue. New
Native/Browser Visit writes use Profile scope. Lists keep their independent scope.
No owner identity, rating, note, restaurant, Visit time or record deletion changes.

The historical data had24 private local Visits,9 private cloud Visits, and no active
local photos. A separate actual sync defect was identified: synthesized Swift JSON
omits nil companion links/deletedAt, while the server required explicit null. Decoder
now accepts omission as null, still rejects invalid non-null values and checks owner
and friendship boundaries. Needed parent/companion mutations are requeued using their
real versions when footprint visibility changes. No fabricated identity or bypass.

Latest now includes the viewer's otherwise-qualified public Visits. Public profile,
Visit rating, city, photo, friends, blocks and moderation gates remain. All24 personal
footprints need not appear in a city/score-filtered public feed.

Validation:11 Native Profile tests (including3 scopes, owner isolation and repeated
reconciliation),74 focused TS/Worker tests including sync, photo authorization and
public sharing. Formal typecheck/stage and built resources match26 files;59 artifact
files scanned, no secret/Offer matches. Main App and ShareExtension identity PASS.

Source/artifact/device: Taste Map Private / DebugPrivatePreview / HYBRID_DEVELOPMENT,
build2026090811, source96ab0604f2ab7668a35b79890f3ddedacbea1979153dbf28ae4293199585e036.
Installed/launched at19:54:19 +0800; matching device diagnostic and verified entitlement.
Development Worker version ab629ee6-e454-4b1b-a96c-c53ae1aa5f0a. No Production deploy,
primary cutover, StoreKit purchase or TestFlight upload.

Private backups: .private/profile-0811-before and -after. First device readback retains
27 Restaurants and24 Visits, zero missing original IDs; all24 Visit scopes public.
Final read-only Development D1 audit confirms all24 nondeleted Visits public.
Physical UI acceptance remains pending; no missing records or direct database edits.

Design System Compliance: canonical Settings/Profile/Visit/Footprint templates remain;
shared Core controls/copy reflect a single scope; Native rollback's competing Visit
picker replaced with the current profile value and explanatory copy. Food/Dining
visuals and cards unchanged. Browser/Capacitor share their existing React components.
No new renderer or duplicate page. Physical UI acceptance remains required.
