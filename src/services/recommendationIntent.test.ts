import { describe, expect, it } from 'vitest'
import { applyRecommendationIntent, browserRecommendationPreferences, recommendationIntent } from './recommendationIntent'

const metadata = (name: string, tags: string[] = []) => ({ name, tags })
function memory() {
  const data = new Map<string, string>()
  return { data, getItem: (key: string) => data.get(key) ?? null, setItem: (key: string, value: string) => { data.set(key, value) } }
}
const card = (id: string, name: string, rank: number, tags: string[] = []) => ({ restaurant: { id, ...metadata(name, tags) }, rank, rating: 9.5, personalTastePercent: 87, reasons: ['真实评分证据'] })

describe('Recommendation intent is distinct from taste ratings', () => {
  it.each(['肯德基（杭州店）', 'ＫＦＣ (West Village)', 'kfc', '麦当劳 · 城西店', "McDonald's (Chelsea)", 'McDonald’s', '绝味鸭脖-南星桥店'])(
    'recognizes only the explicit brand at the start: %s', name => expect(recommendationIntent(metadata(name)).brandID).not.toBeNull())
  it.each(['肯德基旁家常菜', '绝味鸭脖面馆', '老王 KFC 风味炸鸡', 'McDonaldstown Bistro', 'KFCafe', '地方特色小吃', '兰州牛肉拉面', '西湖小吃', '快餐小吃店'])(
    'does not infer brand/intent from misleading names or ordinary cuisine: %s', name => expect(recommendationIntent(metadata(name, ['快餐', '小吃', '炸鸡']))).toEqual({ brandID: null, context: null }))
  it('uses explicit scenario tags only; conflicting tags are unknown', () => {
    expect(recommendationIntent(metadata('午间厨房', ['日常快餐'])).context).toBe('everyday_fast_food')
    expect(recommendationIntent(metadata('外带零食', ['小吃外带'])).context).toBe('snack_takeaway')
    expect(recommendationIntent(metadata('复合餐饮', ['日常快餐', '小吃外带'])).context).toBeNull()
  })
  it('hides same-brand branches but keeps other brands and never changes source ratings/history', () => {
    const items = [card('a', 'KFC (A)', 1), card('b', '肯德基（B店）', 2), card('c', '麦当劳', 3), card('d', '特色炸鸡', 4)]
    const before = JSON.stringify(items)
    const preferences = browserRecommendationPreferences(memory(), 'owner', [['a']], { aliases: ['a'], metadata: items[0].restaurant })
    expect(applyRecommendationIntent(items, preferences).map(item => item.restaurant.id)).toEqual(['c', 'd'])
    expect(JSON.stringify(items)).toBe(before)
    expect(preferences.intentFeedback?.contextCounts).toEqual({ everyday_fast_food: 1 })
  })
  it('learns from distinct restaurants, not repeated clicks or provider aliases; resets by owner', () => {
    const storage = memory()
    const groups = [['a', 'apple:1'], ['b', 'osm:2']]
    browserRecommendationPreferences(storage, 'owner', groups, { aliases: ['a'], metadata: metadata('KFC') })
    browserRecommendationPreferences(storage, 'owner', groups, { aliases: ['APPLE:1'], metadata: metadata('肯德基') })
    const result = browserRecommendationPreferences(storage, 'owner', groups, { aliases: ['b'], metadata: metadata('麦当劳') })
    expect(result.intentFeedback).toEqual({ brandIDs: ['kfc', 'mcdonalds'], contextCounts: { everyday_fast_food: 2 } })
    expect(browserRecommendationPreferences(storage, 'owner', groups)).toEqual(result)
    expect(browserRecommendationPreferences(storage, 'other', groups).intentFeedback).toEqual({ brandIDs: [], contextCounts: {} })
  })
  it('two clear signals lower scene priority without excluding special snacks or altering scores', () => {
    const items = [card('a', '日常午餐', 1, ['日常快餐']), card('b', '特色小吃', 2, ['小吃']), card('c', '火锅', 3), card('d', '另一午餐', 4, ['日常快餐'])]
    expect(applyRecommendationIntent(items, { excludedIDs: [], intentFeedback: { brandIDs: [], contextCounts: { everyday_fast_food: 1 } } })).toEqual(items)
    const result = applyRecommendationIntent(items, { excludedIDs: [], intentFeedback: { brandIDs: [], contextCounts: { everyday_fast_food: 2 } } })
    expect(result.map(item => item.restaurant.id)).toEqual(['b', 'c', 'a', 'd'])
    expect(result.map(item => item.rank)).toEqual([1, 2, 3, 4])
    for (const item of result) expect({ ...item, rank: items.find(v => v.restaurant.id === item.restaurant.id)!.rank }).toEqual(items.find(v => v.restaurant.id === item.restaurant.id))
  })
  it('retains old exclusions without retroactively learning from them', () => {
    const storage = memory(); storage.data.set('tastemap:recommendation-exclusions:v1:owner', '["apple:1"]')
    const result = browserRecommendationPreferences(storage, 'owner', [['a', 'apple:1']])
    expect(result.excludedIDs).toEqual(['a', 'apple:1'])
    expect(result.intentFeedback).toEqual({ brandIDs: [], contextCounts: {} })
  })
  it('merges identities learned later without double-counting the same dismissal', () => {
    const storage = memory()
    browserRecommendationPreferences(storage, 'owner', [], { aliases: ['local'], metadata: metadata('KFC') })
    browserRecommendationPreferences(storage, 'owner', [], { aliases: ['apple:1'], metadata: metadata('KFC') })
    expect(browserRecommendationPreferences(storage, 'owner', [['local', 'apple:1']]).intentFeedback?.contextCounts).toEqual({ everyday_fast_food: 1 })
  })
  it('never upgrades unknown metadata or corrupted persisted data to learned feedback', () => {
    const storage = memory()
    const value = browserRecommendationPreferences(storage, 'owner', [], { aliases: ['local'], metadata: metadata('小吃店') })
    expect(value.intentFeedback).toEqual({ brandIDs: [], contextCounts: {} })
    storage.data.set('tastemap:recommendation-exclusions:v2:owner', '{"excludedIDs":[],"entries":[{"aliases":["x"],"brandID":"invented","context":null}]}')
    expect(() => browserRecommendationPreferences(storage, 'owner', [])).toThrow('推荐偏好读取失败')
    expect(() => browserRecommendationPreferences({ getItem: () => null, setItem: () => { throw new Error('quota') } }, 'owner', [], { aliases: ['a'], metadata: metadata('KFC') })).toThrow('quota')
  })
})
