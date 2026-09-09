# Discovery refresh and avatar — 0812

User reports Latest shows only three cards, old entries and wrong avatar.
Read-only Development audit confirms 24 public Visits: 23 Hangzhou (10 with rating >=7.5/10), one cityless (rated10). Latest personal Visit September5 is rated7; August31 unrated; September1 has no city. Existing canonical qualification and city rules intentionally remain; these are not a complete personal ledger.

Confirmed defects: Hybrid city activity page ignored syncCompleted, so a page queried during historical publishing stayed stale; both activity and similar-taste headers rendered nickname initials despite typed profile avatar fields. Query now refreshes after syncCompleted. Both headers reuse UserAvatar with native authorized photo URI/preset. Session resource permission includes only avatars in current-owner accepted server pages; final photo API authorization remains unchanged.

Validation:55 tests in HybridRemainingUIContract and discoveryCityQuerySession; typecheck/formal stage PASS. Updated obsolete pre-0810 test expecting canonical recommendations to stay loading. New regression covers preset and uploaded avatar source. Build/embedded signing/secret gate PASS. Staged29 bundled files and59 scanned artifact files, no secret matches.

SOURCE/ARTIFACT/DEVICE: Taste Map Private / DebugPrivatePreview; build2026090812; source865f896b200b3d180dd80c1a6c1d770093353b2defcf01a24b0700a1368135b0; device diagnostic confirms HYBRID_DEVELOPMENT at2026-09-08T12:04:01Z. Existing account and data retained. UI card-count/avatar acceptance still requires actual device observation; automated checks are not physical UI PASS.

Consumer inventory: Browser CommunityPage already uses UserAvatar; Capacitor Hybrid Following/Latest ActivityCard and Similar Taste RecommendationCard corrected together. Native DTO already preserves avatar. No restaurant visual/Map/core membership change. No production deployment, cutover, purchase, Offer consumption or TestFlight upload.

## Device acceptance on0813
Lafayette explicitly confirmed Latest10 entries and profile-consistent avatar.
Latest count and avatar: REAL DEVICE PASS. For You/current-city/filter acceptance
remains pending.
