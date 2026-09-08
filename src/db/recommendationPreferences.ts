import { db } from './appDb'
import { emptyBrowserRecommendationPreferenceState, type BrowserRecommendationPreferenceStore } from '../services/browserRecommendationPreferenceSync'

export const browserRecommendationPreferenceStore: BrowserRecommendationPreferenceStore = {
  read: ownerID => db.recommendationPreferences.get(ownerID),
  update: (ownerID, change) => db.transaction('rw', db.recommendationPreferences, async () => {
    const current = await db.recommendationPreferences.get(ownerID) ?? emptyBrowserRecommendationPreferenceState(ownerID)
    const next = change(current)
    if (next.ownerID !== ownerID) throw new Error('推荐偏好账户不匹配。')
    await db.recommendationPreferences.put(next)
    return next
  }),
}
