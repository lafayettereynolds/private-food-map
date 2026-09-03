# Profile + Discovery visual correction evidence

Date: 2026-09-04
Device: iPhone 17 Pro Simulator, iOS 26.5
UDID: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

## Profile

- Following and follower counts sit directly below the profile name.
- Visited, Want to Go, and total spend remain one three-column statistics group.
- The total-spend column has additional width and a fitted currency size.

Evidence: `profile-iphone17pro.png`

## Discovery activity feed

- Activity items use an open, continuous social-feed composition.
- Restaurant media is a compact, left-aligned square rather than a full-width boxed hero.
- Items are separated by a light divider, without a rounded outer card, shadow, or gray inter-card gutter.
- Like, comment, share, and Restaurant actions remain; the Activity footer no longer contains Follow.

Evidence: `discovery-following-iphone17pro.png`

## Runtime chain

- Formal Release React bundle built and staged.
- Staged resources matched the built Release `TasteMap.app` byte-for-byte.
- Release purity scan passed.
- Debug fixture bundle built, staged, compiled, installed, and launched from the exact Debug `TasteMap.app` used for these screenshots.
- Frontend regression suite passed: 62 files, 451 tests.
- iOS test suite passed: 649 tests in 66 suites.
