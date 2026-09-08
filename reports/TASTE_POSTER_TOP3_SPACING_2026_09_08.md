# Taste poster Top 3 spacing

Rank circle x=53 r=15 now has 13px separation from artwork x=81 width=62.
Artwork clip/fallback share center x=112, radius=31; text starts x=154
with a 100px name column. This changes layout only, preserving rank and data.
Regression checks cover image, clipping, rank and name coordinates.
Browser report/poster integration passed; generated F24 preview inspected.

Formal staging BLOCKED by unrelated current-worktree TS2367 at
src/hybrid/app/HybridDiscoveryPage.tsx:148 (recommendationPreferenceSynced).
No new build/install is claimed; unrelated discovery code was not changed.
Core controls unchanged; canonical Taste poster renderer owns the correction;
existing Food Library/image sources unchanged. Native rollback parity not
claimed. No production or physical-device deployment.
