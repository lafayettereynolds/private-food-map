# Automatic Visit Payment and Independent Restaurant Reference

## Outcome and scope

User-approved one-amount input is implemented in Add Restaurant, Record Visit and Edit Visit. AA divides by party size, I-treat pays all, being-treated pays zero, separate/other consumes the owner's entered payment. Profile expenditure and the existing React analysis consumers use the same resolver. Restaurant per-person reference remains independent: a 200 meal for four is reference 50 under AA/I-treat/being-treated, while personal payments are 50/200/0.

No schema, remote deployment, private-account mutation, device migration or real-iPhone installation was performed. Historic explicit personal payments remain authoritative on unrelated edits; changed financial inputs recalculate on save. Missing/unknown multi-person payment modes are not guessed. New separate/other payments never fabricate a table total. Existing reference-only records survive unrelated edits.

## Shared-consumer inventory

| Consumer | Implementation / verification |
| --- | --- |
| Browser and Capacitor add/edit Visit | One `VisitSpendFields` and `AddVisitModal`; mode/amount/party changes, one-input negative contract and reference output covered |
| Browser initial Restaurant Visit | Reuses the same field and calculation primitive; personal modes retain correct per-person reference without a fake table total |
| Hybrid initial Restaurant Visit | Existing shared Visit route uses the same editor and typed save |
| Profile totals and spend details | Same `summarizeVisitSpend` / `resolveVisitActualSpend`; amounts retain cents; actual installed save-refresh tested |
| React taste/companion/source/month/year/anniversary | Existing common spending-resolver callers inherit the correction; focused review/share contracts pass |
| Native rollback editor | One amount input, mode calculation and independent reference output; formal Xcode build passes |
| Native Profile / Restaurant summary / Analysis input projections | Consume `Visit.resolvedActualSpend` rather than independently reading only the nullable personal field |
| Backup / Sync / external reference prices | Storage fields retained; no historical bulk rewrite or schema change |

The earlier name error was a DTO identity mismatch: Native now gives nested Visits their parent's emitted Restaurant ID; shared projection also uses that parent rather than an unrelated local ID. Omitted optional payment keys are handled like null. Shared city projection can recover an explicitly written administrative city from the beginning of an address, never from the user's location or a hard-coded Hangzhou default.

## Tests and actual artifacts

- TypeScript typecheck: PASS.
- 111 focused TypeScript / component / adapter / review / share / global-contract tests: PASS.
- Formal Xcode: 2 VisitSpendPolicy XCTest cases plus 13 Visit core/context tests: PASS.
- 2 installed Hybrid UI tests: PASS, including amount 200 + four people + AA => personal 50.00 and reference 50, save, return to Profile and observe total change without relaunch.
- Two earlier UI attempts failed on test identity/text segmentation. The first selected a same-name background footprint through a modal. The second expected a single accessibility text from split JSX children. Both were corrected and the complete final selection passed; failures are not counted as successful runs.
- Independent `swift test` package remains blocked by existing incomplete package dependencies (`RestaurantVisitStatePolicy` / `categoryDescriptor` among others). It is not reported as passing; the formal Xcode App and selected App tests are the verified Native path.
- Final results: `/tmp/tastemap-automatic-payment-final.xcresult`.
- AA/reference runtime screenshot: `/tmp/tastemap-automatic-payment-final-attachments/44DA143A-F609-4442-8E5C-85D2BAD77829.png`.
- Updated total screenshot: `/tmp/tastemap-automatic-payment-final-attachments/CBFC6ABB-B709-4CCC-97B1-88D7E8E168E7.png`.
- Screenshots use isolated Rich QA data, not Lafayette's private account.

Formal resource chain passed: source → dist → formal staging → built `.app` → installed `.app`, 16 resources byte-for-byte. Final JS `index-WVR6jDga.js`, CSS `index-ZmVsvhdK.css`.

Visible device: iPhone 17 Pro Simulator `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`; scheme TasteMap QA / DebugQA; bundle `com.lafayette.tastemap.qa`. Built app `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`; final installed app ends `BC1FCD43-33D9-43A0-9315-5AF841795C4B/TasteMap.app`. Launch environment `TASTEMAP_CORE_PARITY_INITIAL_TAB=profile`. Runtime is React Hybrid with existing Native services, not Native rollback. Branch `feature/hybrid-final-integration`, existing dirty worktree preserved; no commit or route-owner switch.

Read-only replay of the private 11:02 snapshot yields 291.68 across 9 computable Visits, with 14 unresolved (11 lack a multi-person payment choice, 3 lack an amount). This is a timestamped diagnostic result, not a current-phone balance and not a database mutation.

## Design System Compliance

- Core UI: reused shared ModalShell, fields, choice controls, StickyFormActionBar and existing visual scale; one coherent calculated-reference group, no second editable payment field.
- Food & Dining visuals: unchanged; no generated or substituted imagery.
- Canonical Page Templates: existing dining-diary flow, context, ratings, notes, companions, photos and save action retained. Profile and Restaurant information architecture retained.
- Matching duplicate amount-input implementations remaining: 0 in the audited React and Native editor source. Native and React financial primitives are equivalent platform implementations, with corresponding cases tested.
- No new default-SwiftUI visual variant introduced. Updated normal-size Hybrid editor and Profile runtime were inspected. Browser verification is component/contract based; Native rollback full visual and accessibility-size sweeps were not rerun, so no claim of complete global visual acceptance is made.
- Durable rules recorded in `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` under Visit Editor.
