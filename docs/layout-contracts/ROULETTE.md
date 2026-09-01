# Restaurant Roulette Layout Contract

Reference: approved historical Web wheel and candidate-manager evidence.

## Main page order

1. Compact title and concise two-line explanation.
2. One `已选候选` panel containing removable real Restaurant chips,
   source/city conditions, count, and `管理候选餐厅`.
3. One wheel.
4. Result card and reroll behavior.
5. Concise local/offline note.

No duplicate candidate count/filter panel or second toolbar filter action.

## Wheel geometry

- Two to ten unique Restaurant identities are eligible.
- The pool, candidate chips, visual segments, pointer, and result are one-to-one.
- Unfilled positions say `+ 添加更多餐厅`; they are not selectable data.
- No Restaurant is copied to fill geometry.
- Pointer is anchored above the circle; center action is centered; labels stay
  inside their segment with a readable size and contrast.
- Restaurant media/name/city/rating use the canonical image and semantic data.

## Candidate manager

Search, `全部 / 去过 / 想吃`, real Restaurant rows, select/deselect, maximum
ten, explicit Apply, and one route to the official Manual Add flow. Cancel does
not mutate the applied pool.

## States

Empty, one candidate, two, five, ten, large library, missing photo, long name,
result, reroll, persisted restart, offline, Light/Dark, Reduce Motion, and
Dynamic Type.
