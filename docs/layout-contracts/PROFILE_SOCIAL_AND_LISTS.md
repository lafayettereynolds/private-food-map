# Profile, Social, and Lists Layout Contract

## My Profile dashboard

1. Compact identity header: avatar, name, city/joined date, edit, Premium.
2. Following and followers at the same relationship level.
3. One horizontal statistics row: unique `去过`, active `想去`, valid
   `总消费`.
4. Paired primary entrances: `今天吃什么 / 我的口味档案`.
5. One `回味` row/group: `本月回顾 / 年度回顾 / 那年今日`.
6. `我的食单` with the real Lists entry.
7. `发现与洞察`: `最佳饭搭子 / 谁最会种草`.
8. Independent `味觉足迹`.
9. Settings as a secondary utility entry.

The screen is a dense dashboard, not a sequence of oversized single-purpose
cards. Current-only social, Premium, Analytics, settings, and data-safety
capabilities are preserved.

## Public profile/social

Public identity, follow/friend state, allowed statistics, public activities,
public Lists, and privacy/safety actions are ordered from identity → relationship
→ content. Private/deleted/blocked content is not left as an empty card shell.

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
