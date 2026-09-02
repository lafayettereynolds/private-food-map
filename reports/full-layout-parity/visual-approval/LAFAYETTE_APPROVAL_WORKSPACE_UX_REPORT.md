# Lafayette Visual Approval Workspace UX Report

Date: 2026-09-02  
Branch: `fix/product-ux-correction-8-tasks`  
Scope: `reports/full-layout-parity/visual-approval/` only

## Outcome

The visual approval tool now supports a stable, convergent page-review workflow without changing the viewport after each region decision.

- Desktop uses a sticky two-column workspace: visual evidence on the left, region decisions on the right.
- Narrow windows use a collapsible visual panel above the region decisions without horizontal overflow.
- Region decisions update locally. The full page is not re-rendered and the screenshot gallery is not revisited.
- Current page, current region, approximate scroll position, pinned comparison, clean-preview selection, panel state, lightbox image and lightbox zoom are persisted locally.
- A “next pending region” action advances within the current page before moving to the next page.
- Opening and closing the image viewer restores the approval viewport recorded when the viewer was opened.

## Profile-specific workspace

The Profile review workspace follows Lafayette's requested geometry:

- Left: fixed `Profile FUSE V2` visual evidence.
- Fixed regions shown as non-editable context: `顶部身份区`, `设置`.
- Right: exactly six selectable regions:
  - `关注数据`
  - `主统计`
  - `核心入口`
  - `回味`
  - `我的食单`
  - `洞察`

Existing decisions, frozen regions, notes, uploaded references and page decisions remain intact.

## Candidate-only labels and Clean Preview

`FUSE V1/V2/V3`, candidate-version descriptions, change-scope descriptions, and frozen/pending approval states are explicitly treated as local approval metadata.

They are not product UI and must not appear in Taste Map formal pages or Release UI.

The sticky visual panel has a `无候选标识预览` mode:

- A current/legacy/user reference that is already clean is displayed without approval-tool labels.
- A candidate that has an explicit clean screenshot can display that clean screenshot.
- A candidate screenshot with labels baked into the pixels is never cropped, painted over, or presented as a clean screenshot.
- When no clean screenshot exists, the tool displays `Clean Preview 尚未提供` and explains that a new screenshot must be rendered from the candidate implementation without DEBUG/candidate overlays.

At the time of this report, `Profile FUSE V2` contains candidate labels inside the screenshot itself. Its Clean Preview therefore correctly reports that a separate clean render is still required.

## Verification

| Check | Result |
| --- | --- |
| Visual approval pages | 14 present |
| Profile left visual | `round-2/candidates/profile-fuse-v2.png` |
| Profile selectable regions | Exactly 6, matching the approved list |
| Profile fixed regions | `顶部身份区`, `设置` |
| Region decision update | Local DOM/state update; no full render |
| Consecutive decision scroll delta | `0 px` after the first browser automation actionability adjustment |
| Image viewer close | Restored the scroll position captured at the actual open event |
| Refresh recovery | Restored `scrollY = 46558`, Profile page, Core Entries and pinned FUSE V2 |
| Next pending region | Advanced from Map title to `去过 / 想吃 / 推荐` |
| Clean Preview for labeled FUSE V2 | No fake image; honest missing-clean state |
| Narrow viewport | No multi-thousand-pixel horizontal overflow; workspace fits the viewport |
| JavaScript syntax | PASS for `app.js`, `round2-data.js`, `round3-data.js`, `reference-library.js` |
| Git whitespace check | PASS |
| Formal Swift source candidate-label scan | `0` matches |

The one failed `img` element reported by a raw DOM scan is the empty lightbox placeholder (`src` absent) while the dialog is closed, not a missing approval screenshot.

## Product safety boundary

- No Swift or SwiftUI source changed.
- No Taste Map business logic changed.
- No Simulator state changed.
- No Production system was accessed or modified.
- No approval decision was automatically promoted to the formal product.
