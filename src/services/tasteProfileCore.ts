export interface TastePreferenceSignal {
  restaurantKey: string
  tags: string[]
  ratingOutOfTen: number
}

export interface RankedTasteTag {
  tag: string
  score: number
  visits: number
  averageRating: number
  highRatingShare: number
  repeatVisits: number
}

/** Shared, platform-neutral preference scoring used by Taste Profile and Discover. */
export function rankTasteTags(signals: TastePreferenceSignal[]): RankedTasteTag[] {
  const values = new Map<string, { ratings: number[]; restaurantCounts: Map<string, number> }>()
  signals.forEach((signal) => signal.tags.forEach((rawTag) => {
    const tag = rawTag.trim()
    if (!tag) return
    const key = tag.toLocaleLowerCase('zh-CN')
    const value = values.get(key) ?? { ratings: [] as number[], restaurantCounts: new Map<string, number>() }
    value.ratings.push(signal.ratingOutOfTen)
    value.restaurantCounts.set(signal.restaurantKey, (value.restaurantCounts.get(signal.restaurantKey) ?? 0) + 1)
    values.set(key, value)
  }))

  return [...values].map(([tag, value]) => {
    const visits = value.ratings.length
    const averageRating = value.ratings.reduce((sum, rating) => sum + rating, 0) / visits
    const highRatingShare = value.ratings.filter((rating) => rating >= 8).length / visits
    const repeatVisits = [...value.restaurantCounts.values()].reduce((sum, count) => sum + Math.max(0, count - 1), 0)
    const score = averageRating * 0.48 + highRatingShare * 3 + Math.log2(visits + 1) * 1.15 + Math.log2(repeatVisits + 1) * 0.75 + Math.min(3, value.restaurantCounts.size) * 0.2
    return { tag, score, visits, averageRating, highRatingShare, repeatVisits }
  }).sort((a, b) => b.score - a.score || b.visits - a.visits || b.averageRating - a.averageRating)
}
