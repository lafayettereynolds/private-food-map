# Profile, Social, and Lists Layout Contract

## My Profile dashboard

1. Compact identity header: avatar, name, city/joined date, Premium. The explicit
   `编辑资料` entry belongs only in Settings → Account and Security; omit the
   dashboard button and any empty action-row space, preserving existing avatar
   behavior and all other identity actions.
2. Following and followers at the same relationship level.
3. One horizontal statistics row: unique `去过`, active `想去`, valid
   `总消费`.
4. Paired primary entrances: `今天吃什么 / 我的口味档案`.
5. One `回味` row/group: `本月回顾 / 年度回顾 / 那年今日`.
6. `我的食单` with the real Lists entry.
7. `发现与洞察`: `最佳饭搭子 / 谁最会种草`.
8. Independent `味觉足迹`: every durable Visit and current Want to Go save,
   merged into one reverse-chronological private timeline.
9. Settings as a secondary utility entry.

The screen is a dense dashboard, not a sequence of oversized single-purpose
cards. Current-only social, Premium, Analytics, settings, and data-safety
capabilities are preserved.

The owner summary uses shared `ProfileSummary` tokens, not page-local padding:
8 pt below identity, 4 pt statistic row vertical inset, at least 44 pt per
statistic button, and 10 pt to the paired primary entrances. Keep all three
statistics, original amount font and wider amount column. This is a narrow
whitespace correction, not permission to shrink text or reorder the dashboard.

`味觉足迹` sits directly after `发现与洞察` and before settings. Visit entries
use the actual dining time and remain visible when unrated; current Want to Go
entries use their first-saved time. Discovery eligibility rules never filter
this owner history, and every visible rating uses the 10-point presentation.

## Public profile/social

Public identity starts with avatar/name/stable ID, then the same compact
`关注 / 粉丝` metadata used on My Profile, then city and the real joined month.

The native Social Hub exposes exactly four peer sections in order: `好友 / 关注 / 粉丝 / 推荐`. `好友` is computed from reciprocal follows, never from a one-sided action or a legacy request state. Search and explainable people suggestions live together under `推荐`.
Friend/follow actions stay with that identity block. Content is stacked rather
than hidden behind a primary toggle: permission-authorized public food map →
independent `食单` section → independent `动态` section. Inside `动态`,
`到访 / 想吃` filters the one `去过公开记录` block; those values are not
repeated as detached hero statistics. The map is built only from visible remote
records with valid stored coordinates and opens the same Restaurant destination
as the record card. Private/deleted/blocked content is not left as an empty card
shell. Loading, true-empty, cached, partial-failure, and unavailable states are
visibly distinct; fixed Demo data is allowed only behind an explicit test-mode
gate and never enters normal Debug or Release paths.

## Lists

- Overview: title/search/create, then dense visual list cards.
- Detail: cover/identity/visibility/actions, then ordered Restaurant members.
- Ranked Lists visibly preserve rank; public/private state is clear but not the
  dominant hero.
- Restaurant rows use the canonical image renderer and standard Detail route.
- Empty list and zero-search states use the canonical state system.

## States

Logged in/out, Free/Premium, long/missing identity data, missing avatar, zero and
rich stats, social loading/error/private/blocked, empty/normal/ranked/public/
private/long-title/10+ Restaurant Lists, missing images, Light/Dark, Dynamic
Type, and small screen.
