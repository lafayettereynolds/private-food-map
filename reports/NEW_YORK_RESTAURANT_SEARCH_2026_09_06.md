# New York restaurant search — scoped diagnosis and source correction

Status: source correction and focused JS regressions PASS; native test execution,
installed-runtime and physical-iPhone original-query acceptance PENDING.

## Observed request and independent evidence

The screenshot submitted `Da Andrea Greenwich Village` with city `new york`.
The nearby GPS-unavailable state is separate from the explicit-city search.

The restaurant's official website lists Greenwich Village at **35 W 13th St,
New York, NY 10011**, and Chelsea separately at **160 8th Ave**:
https://daandreanyc.com/ . Apple Maps also has the Greenwich Village listing:
https://maps.apple.com/place?place-id=I4F3963C426A62D2C . These are existence/address
checks, not an authorization to inject merchant data into production search.

Read-only live Photon requests on 2026-09-06 used the public New York city centre,
not the user's GPS. The full query returned neighbourhood/street suggestions and
the unrelated restaurant `Top Thai Greenwich`, but not Da Andrea. The short query
`Da Andrea` returned both real branches. Its original 35 West 13th Street record
has `locality: Union Square`, not Greenwich Village. Consequently simply dropping
the neighbourhood restriction or manufacturing an alias would risk selecting the
wrong branch and was deliberately not done.

## Confirmed defects corrected

1. `WorldwideRestaurantSearchService` treated any non-empty dining-provider batch
   as a hit before the outer relevance filter. An unrelated Photon restaurant
   therefore prevented MapKit fallback; the outer filter removed it and displayed
   an empty result. Both provider preference branches now use the existing shared
   relevance policy *before* declaring a successful match. Fallback results are
   filtered through the same policy. No name, ranking or coordinate is hardcoded.
2. `MapKitRestaurantSearchService.mapItemDistrict` on iOS 26 returned
   `addressRepresentations.cityWithContext` before reading actual sub-locality.
   The installed SDK documents this property as `Cupertino, CA`, not a
   neighbourhood. The projection now preserves actual provider `subLocality`,
   then `subAdministrativeArea`, before falling back to city context. This retains
   available evidence for exact name-plus-neighbourhood matching.

`new york`, `NewYork`, and `纽约` already canonicalize to New York. No city alias or
GPS accuracy change was necessary. No permission request, GPS substitution, city
centre pretending to be GPS, broad fuzzy acceptance, special merchant ranking,
provider deployment, database mutation or analytics/poster change was made.

## Consumer inventory and tests

- Native acquisition, Native search/edit consumers, ordinary app and Hybrid
  acquisition all instantiate the same Worldwide service; they receive the fix.
- Browser remains its existing AMap provider; its existing strict name/address/
  district relevance is covered with the identical three-candidate branch case.
  This task does not claim newly added worldwide Browser provider coverage.
- Three Swift tests added to `RestaurantAcquisitionTests`: irrelevant foreign
  response proceeds to fallback while preserving explicit city and nil GPS;
  relevant foreign response avoids unnecessary fallback; name-plus-neighbourhood
  rejects the wrong branch and unrelated restaurant. Existing city-alias test
  additionally covers the submitted lowercase spelling.
- Five focused JS suites / 23 tests PASS (`mapService`, acquisition source
  contracts, search-location, restaurant-city and Browser-city-source).
- Swift syntax parse and scoped `git diff --check` PASS.

## Remaining acceptance boundary

Native Swift tests await the coordinating agent's canonical Xcode run. No stage,
build, install, simulator interaction, phone sync or release occurred in this
subtask. A separate read-only macOS MapKit probe for the exact original query
failed with MKErrorDomain 4 / GEO -8, so it cannot prove live MapKit success.

Run the exact original query on the freshly built iPhone, with GPS unavailable
as well as available. Confirm the returned restaurant's real address and that
Chelsea is not mislabeled as Greenwich Village. The source fixes remove verified
failure paths but **do not yet establish that the original full-name query is
successfully resolved on the user's phone**. The short-name public-provider
response is diagnostic evidence, not a replacement for that acceptance step.

## Design-system boundary

Core acquisition controls/states, Food/Restaurant visual source policy and the
canonical Add template are unchanged. No new layout, icon, default-SwiftUI style,
duplicate renderer or route ownership change. Visual acceptance is not claimed.
