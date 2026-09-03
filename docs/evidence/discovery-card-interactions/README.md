# Discovery Card interaction evidence

Validated on the fixed acceptance destination:

- iPhone 17 Pro
- iOS 26.5
- UDID `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`
- Debug-only deterministic Visual QA data; no Production endpoint or mutation was used

The approved Discovery Card composition was not redesigned. The current Product Contract exposes three Restaurant actions—Record Visit, WantToGo and Roulette—and no Discovery Card List shortcut. List remains available in the rest of Taste Map. Restaurant-qualified accessibility labels ensure every probe targets one explicit Card instead of another offscreen Card with the same icon label.

Current final footer evidence:

- [Browser complete Card footer — exact 3 + 3 actions](08-full-card-footer.png)
- [Capacitor complete Card footer — fixed iPhone 17 Pro simulator](09-capacitor-full-card-footer.png)

| Control | Explicit target / route | Actual visible result | Return-state verification | Evidence |
| --- | --- | --- | --- | --- |
| Like / Unlike | `activityID? + visitID + authorID + restaurantID` → `community.setLike` | Heart selection and count change immediately; native authoritative result settles; second tap restores the original state | `为你推荐` remains selected and the same Card footer remains in view | [Like selected](01-like-after.png) |
| Comment | Same Activity/Visit identity → `community.comments` / `community.addComment` | Current Card's comment surface opens and displays the submitted comment | Close returns to the selected tab and same Card position | [Current Activity comment](02-comment-current-activity.png) |
| Record Visit | Restaurant ID → shared Hybrid `visit` route | Existing Batch 2 Visit Editor opens with the Restaurant prefilled; save succeeds | Save returns to the selected Discovery tab and same Card position | [Visit Editor](03-record-visit-editor.png) |
| WantToGo add/remove | Restaurant ID → `restaurant.setWantToGo` | Enabled `none` fixture changes to selected `want_to_go`; mutation is busy/disabled until authoritative settle; remove restores `none` | Discovery tab and Card position remain unchanged | [WantToGo selected](04-want-to-go-after-add.png) |
| Roulette | Restaurant ID → shared Hybrid `roulette` route | Existing Hybrid Roulette page opens with the candidate context; no `openNative` handoff occurs | Close returns to the selected tab and same Card position | [Hybrid Roulette](06-roulette-hybrid-route.png) |
| Share | Restaurant name/text → native system share capability | iOS system share sheet opens | Dismiss returns to the selected Discovery tab | [System Share](07-system-share.png) |

Automated contract coverage additionally verifies rollback after Like failure, browser persistence for WantToGo after reload, correct Restaurant identity for Visit/Roulette, absence of the Discovery List shortcut, continued availability of List outside Discovery, and rejection of Hybrid-owned pages by `openNative`.
