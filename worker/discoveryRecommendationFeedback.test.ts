import { describe, it, expect } from 'vitest'
import { applyDiscoveryRecommendationFeedback } from './discoveryRecommendationFeedback'
const candidate = (id:string, tags:string[] = []) => ({card:{restaurant:{globalKey:id,name:id,tags,placeIdentities:[]}},score:9})
const event = (id:string) => ({eventID:id, aliases:[id], source:'explicit_dismissal' as const, occurredAt:'2026-09-08T00:00:00Z', intent:{classifierVersion:1 as const, brandID:null,context:'everyday_fast_food' as const}})
describe('actual ranking feedback',()=>{
  it('excludes first, then lowers repeated dining-intent contexts without changing scores or cuisine',()=>{
    const items=[candidate('hidden'),candidate('quick',['日常快餐']),candidate('dinner',['川菜']),candidate('snack',['小吃'])]
    const result=applyDiscoveryRecommendationFeedback(items,{revision:2,events:[event('hidden'),event('another')]},true)
    expect(result.map(x=>x.card.restaurant.globalKey)).toEqual(['dinner','snack','quick'])
    expect(result.every(x=>x.score===9)).toBe(true)
    expect(items).toHaveLength(4)
  })
  it('one venue and alias retries cannot create a category vote twice',()=>{
    const items=[candidate('quick',['日常快餐']),candidate('dinner')]
    expect(applyDiscoveryRecommendationFeedback(items,{revision:2,events:[event('hidden'),{...event('retry'),aliases:['hidden','other-id']}]},true)).toEqual(items)
  })
  it('explicit sorting preserves order, while still excluding the restaurant',()=>{
    const items=[candidate('quick',['日常快餐']),candidate('hidden'),candidate('dinner')]
    expect(applyDiscoveryRecommendationFeedback(items,{revision:2,events:[event('hidden'),event('another')]},false).map(x=>x.card.restaurant.globalKey)).toEqual(['quick','dinner'])
  })
})
