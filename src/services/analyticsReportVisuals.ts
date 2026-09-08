import type { TasteMapProfileDashboardViewModel } from '../platform/TasteMapPlatform'
import type { AnalysisVisualRef } from '../types/analysisShare'
import type { RestaurantSummary, Visit } from '../types/domain'

/** Freeze owner dining-photo evidence with the report, never a Restaurant avatar.
 * Callers supply the already owner/tombstone/period/person-scoped Visit snapshot.
 */
export function analyticsReportVisuals(profile: TasteMapProfileDashboardViewModel, restaurants: RestaurantSummary[], visits: Visit[]) {
  const output: Record<string, AnalysisVisualRef> = {}
  const owners = new Set([profile.user.id, profile.analyticsIdentity?.ownerUserID === profile.user.id ? profile.analyticsIdentity.recordOwnerID : profile.user.id])
  for (const restaurant of restaurants) {
    const base = { label: restaurant.name, restaurantId: restaurant.id, tags: [...restaurant.tags] }
    const descriptor = profile.restaurantImages[restaurant.id]
    const scoped = visits.filter(visit => visit.restaurantId === restaurant.id).sort((a, b) => Date.parse(b.visitedAt) - Date.parse(a.visitedAt) || a.id.localeCompare(b.id))
    const candidates = scoped.flatMap(visit => [
      ...Array.from({ length: Math.max(visit.photos.length, visit.photoIds.length) }, (_, index) => ({ source: visit.photos[index] || null, photoId: visit.photoIds[index] || null, visitID: visit.id })),
      ...visit.dishes.map(dish => ({ source: dish.imageData || null, photoId: dish.photoId || null, visitID: visit.id })),
    ])
    const actual = candidates.find(candidate => {
      if (!candidate.source && !candidate.photoId) return false
      // A denied capability for this exact owner photo cannot be bypassed by its
      // duplicate Visit URL/ID. Other users' descriptors never authorize exports.
      return !(descriptor?.kind === 'ownerPhoto' && !descriptor.exportAllowed
        && ((candidate.photoId && candidate.photoId === descriptor.photoID) || candidate.source === descriptor.resourceURL))
    })
    if (actual) {
      output[restaurant.id] = { ...base, source: actual.source, photoId: actual.photoId, origin: 'visit' }
      continue
    }
    // Native may supply a display URL separately from Visit ID-only rows. Require
    // actual scoped Visit provenance; generic nativeResource/merchant/avatar is not proof.
    if (descriptor?.kind === 'ownerPhoto' && descriptor.exportAllowed && owners.has(descriptor.sourceOwnerID)
      && descriptor.restaurantID === restaurant.id && descriptor.visitID != null && scoped.some(visit => visit.id === descriptor.visitID)) {
      output[restaurant.id] = { ...base, source: descriptor.resourceURL, photoId: descriptor.photoID, origin: 'visit' }
    } else output[restaurant.id] = { ...base, source: null, photoId: null, origin: 'fallback' }
  }
  return output
}
