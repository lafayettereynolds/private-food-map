# Taste Map Full Product Parity — Module 1: Map, List and Personal Filters

## Scope

This module restores the personal restaurant browser only:

- `MapHomeView`
- the shared Map/List query and filter state
- the compact list presentation
- real list-row actions
- stable accessibility identifiers and layout regression coverage

It does not change Restaurant acquisition, GPS/Nearby, Restaurant identity, persistence schemas, synchronization, authentication, Worker, D1 or Production.

## Source of truth amendment

The latest confirmed product direction supersedes the earlier bottom-right-only Map/List control:

- a visible top breathing area and title `我的地图`;
- the personal-state control keeps `去过 / 想吃 / 适合你`;
- Map/List is a compact icon control beside the state control;
- filters are one horizontally scrollable row of compact chips;
- Map remains the main visual surface;
- `+ 添加餐厅` remains bottom-centred and does not overlap the tab bar or location control.

## Step A — function and data semantics

### Web source semantics

The Web personal browser is a projection of the current user's Restaurant and Visit records. The page state selects visited, want-to-go or suitable restaurants; search, filter and sort operate on that same projection. Switching between Map and List must not create another query or lose active filter state.

List actions have product meaning:

- `再次记录` creates another independent Visit for the same Restaurant;
- `想吃` reflects the Restaurant's personal status and must not overwrite Visit history;
- `今天吃` passes the selected Restaurant into the existing roulette flow;
- selecting the Restaurant row opens the shared Restaurant Detail, independently from the row actions.

### iOS implementation contract

- Map and List both consume `filterResult.items` produced from the same `PersonalRestaurantBrowseSnapshot`, `RestaurantFilterState` and `browseQuery`.
- Map/List switching changes presentation only; it does not rebuild or reset the personal query.
- active filter count and chip labels come from the real filter state.
- `再次记录` opens the existing `VisitEditorView`.
- removing an existing want-to-go record uses the existing local-first store and soft-delete/sync path.
- a visited Restaurant is not destructively converted to want-to-go; the user receives an honest explanation.
- `今天吃` opens the existing roulette screen with the selected Restaurant.
- the Restaurant row continues to open the shared local `RestaurantDetailView`.

## Step B — layout contract

| Area | Web / confirmed source | iOS before | Restored iOS | Result |
|---|---|---|---|---|
| Top offset | visible breathing room | controls started immediately without a page identity | safe-area breathing room plus `我的地图` | PASS |
| Page identity | personal map | no explicit title | `我的地图` | PASS |
| Personal states | three primary states | present, mixed with unrelated layers | compact `去过 / 想吃 / 适合你` control | PASS |
| Map/List | compact presentation switch | legacy/ambiguous identifiers and earlier competing placement | compact icon control adjacent to personal states | PASS |
| Filters | single horizontally scrolling chip row | visually heavy/multi-layer impression | one compact chip row with active state/count | PASS |
| Map area | main first-screen surface | reduced by stacked controls | map begins directly below the bounded header | PASS |
| Add CTA | bottom-centred | present | preserved above tab bar, independent from mode control | PASS |
| List hierarchy | contextual personal list | generic rows with no result context | personal eyebrow/title, result count, compact rows | PASS |
| List actions | real independent actions | row-level affordances were incomplete/ambiguous | record, want-to-go and roulette actions are independent of row navigation | PASS |
| Shared state | same query for Map and List | partially covered | same snapshot, query, filter and sort state | PASS |
| Accessibility | readable controls and actions | unstable tab/control lookup | stable tab, mode, row and action identifiers; icon controls labelled | PASS |

## Evidence

### Web reference

- [Web Map before/reference](full-product-parity-assets/web-map-before.jpg)
- [Web List before/reference](full-product-parity-assets/web-list-before.jpg)

### iOS before

- [iOS Map before](full-product-parity-assets/ios-map-before.png)
- [iOS List before](full-product-parity-assets/ios-list-before.png)

### iOS after

- [iOS Map after](full-product-parity-assets/ios-map-after-module-1.png)
- [iOS List after](full-product-parity-assets/ios-list-after-module-1.png)

The after images are exported from the passing `testCoreProductLayoutParityMapDiscoveryProfileEvidence` run on iPhone 17 Pro Max rather than from an intermediate manual build.

## Verification

- iPhone 17 Pro Max, light appearance: PASS
- iPhone 17 Pro Max, dark appearance: PASS
- iPhone 17e small-screen layout: PASS
- Map to List and List to Map: PASS
- active filters and horizontal chips: PASS
- state/query preservation: PASS
- row versus action hit targets: PASS
- Add Restaurant and tab-bar non-overlap: PASS
- `MapBrowsingParityTests`: PASS
- `F2BPersonalRestaurantFilterTests`: PASS
- Debug Simulator build: PASS
- Release Simulator build: PASS

## Remaining work outside this module

- Restaurant acquisition and GPS/Nearby parity is Module 2.
- Discovery's five-tab data semantics and layout is Module 3.
- Profile statistics and topology is Module 4.
- Cross-entry Restaurant Detail unification is a later dedicated module.
- Analytics uses a separate Analysis Theme and is not styled by this Core App module.
