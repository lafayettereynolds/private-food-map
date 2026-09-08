import { normalizeRecommendationPreferenceEventV1 } from '../src/contracts/recommendationPreferencesV1'
import { expandRecommendationAliases } from '../src/services/recommendationExclusions'
import { mergeRecommendationIntentEntries, recommendationIsDismissed, recommendationIntent, summarizeRecommendationIntent } from '../src/services/recommendationIntent'

/** Read private feedback before ranking/pagination. A changed revision invalidates
 * continuation so a new exclusion cannot silently skip/repeat the old page tail. */
export async function readDiscoveryRecommendationFeedback(database: D1Database, owner: string) {
  const rows = await database.prepare(`SELECT revision,payload_json FROM recommendation_preference_events
    WHERE user_id = ? ORDER BY revision LIMIT 10001`).bind(owner).all<{revision:number;payload_json:string}>()
  if (rows.results.length > 10000) throw new Error('recommendation_feedback_capacity_exceeded')
  return { revision: rows.results.at(-1)?.revision ?? 0,
    events: rows.results.map(row => normalizeRecommendationPreferenceEventV1(JSON.parse(row.payload_json))) }
}

export function applyDiscoveryRecommendationFeedback<T extends { card: { restaurant: {
  globalKey: string; name: string; tags: string[]; placeIdentities: Array<{provider:string;externalId:string}>
} } }>(items: T[], feedback: Awaited<ReturnType<typeof readDiscoveryRecommendationFeedback>>, adjustOrder: boolean): T[] {
  const groups = items.map(({card}) => [card.restaurant.globalKey, ...card.restaurant.placeIdentities.map(id => `${id.provider}:${id.externalId}`)])
  const entries = feedback.events.filter(event => event.intent && event.source !== 'legacy_exclusion').map(event => ({
    aliases: event.aliases, brandID: event.intent!.brandID, context: event.intent!.context,
  }))
  const intentFeedback = summarizeRecommendationIntent(mergeRecommendationIntentEntries(entries, [...groups, ...feedback.events.map(event => event.aliases)]))
  const excludedIDs = expandRecommendationAliases(feedback.events.flatMap(event => event.aliases), [...groups, ...feedback.events.map(event => event.aliases)])
  const retained = items.filter(({card}) => !recommendationIsDismissed({ ...card.restaurant, id: card.restaurant.globalKey }, {excludedIDs,intentFeedback}))
  if (!adjustOrder) return retained
  // Willingness to make a dining trip, never cuisine aversion or a rating change.
  // Two different dismissed venues are required; retries/aliases are one vote.
  const penalty = (item:T) => {
    const context = recommendationIntent(item.card.restaurant).context
    return context && (intentFeedback.contextCounts[context] ?? 0) >= 2 ? 1 : 0
  }
  return retained.map((item,index)=>({item,index})).sort((a,b)=>penalty(a.item)-penalty(b.item)||a.index-b.index).map(({item})=>item)
}
