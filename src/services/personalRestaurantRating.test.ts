import { describe, expect, it } from 'vitest'
import cases from '../../hybrid/fixtures/personal-rating-precision.json'
import fixture from '../../hybrid/fixtures/profile-restaurant-rich.json'
import type { Restaurant, Visit } from '../types/domain'
import { projectPersonalRestaurantRating } from './personalRestaurantRating'
import { buildRestaurantSummaries } from './restaurantSummaryProjection'
import { personalRestaurantRating as detailRating } from './ratingConfidence'
import { decodeSyncPushRequest } from '../contracts/syncV1'

const restaurant = { ...fixture.restaurants[0], id: 'restaurant', userId: 'owner', overallRating: null, deletedAt: null } as unknown as Restaurant
function visit(rating: number | null, index: number): Visit {
  return { ...fixture.restaurants[0].visits[0], id: `visit-${index}`, userId: 'owner', restaurantId: restaurant.id,
    rating, deletedAt: null, updatedAt: '2026-09-01T00:00:00Z' } as Visit
}
describe('personal Restaurant final ten-point precision', () => {
  for (const c of cases) it(c.name, () => {
    const values = c.ratings.map(visit)
    const result = buildRestaurantSummaries([restaurant], values)[0]
    expect(result.scoreOutOfTen).toBe(c.expected)
    expect(detailRating(values,'owner').score).toBe(c.expected)
    expect(result.averageRating).toBe(c.ratings.length ? c.ratings.reduce((s,r)=>s+r,0)/c.ratings.length : null)
    expect(projectPersonalRestaurantRating(c.ratings).scoreOutOfTen).toBe(c.expected)
    // Recompute after a serialized local reload; no aggregate write/cache needed.
    expect(buildRestaurantSummaries([restaurant], JSON.parse(JSON.stringify(values)))[0].scoreOutOfTen).toBe(c.expected)
  })
  it('excludes null, deleted and foreign-owner records while retaining unrated Visit count', () => {
    const values = [visit(4,0),visit(4.5,1),visit(null,2),{...visit(1,3),deletedAt:'2026-09-02T00:00:00Z'},
      {...visit(1,4),userId:'someone-else'}, {...visit(1,5),restaurantId:'another'}]
    const before=JSON.stringify(values)
    const result=buildRestaurantSummaries([restaurant],values)[0]
    expect(result.scoreOutOfTen).toBe(8.5);expect(result.averageRating).toBe(4.25);expect(result.visitCount).toBe(3)
    expect(buildRestaurantSummaries([{...restaurant,deletedAt:'2026-09-02T00:00:00Z'}],values)).toEqual([])
    expect(JSON.stringify(values)).toBe(before)
  })
  it('preserves existing legacy explicit Restaurant override without writing it', () => {
    expect(buildRestaurantSummaries([{...restaurant,overallRating:8}], [visit(4.5,0)])[0].scoreOutOfTen).toBe(8)
  })
  it('keeps precise ranking inputs even when the output rounds to the same tenth', () => {
    const a=projectPersonalRestaurantRating([...Array(18).fill(4.5),5])
    const b=projectPersonalRestaurantRating([...Array(19).fill(4.5),5])
    expect(a.averageRating!).toBeGreaterThan(b.averageRating!);expect(a.scoreOutOfTen).toBe(b.scoreOutOfTen)
  })
  it('formal Sync decode preserves legal raw ratings; rejects arbitrary Visit fractions', () => {
    const raw=JSON.parse(JSON.stringify(visit(4.5,0)))
    // Fixture has UI-only associations; supply the formal sync payload fields.
    const payload={...raw,schemaVersion:1,diningMode:'dine_in',visibility:'private',partySize:null,totalPrice:null,
      paymentMode:null,pricePerPerson:null,myActualSpend:null,queueDuration:null,companionIds:[],
      recommendationSourceId:null,recommendationSourceType:null,recommendationSourceUserId:null,recommendationSourceText:null,sharedMealId:null}
    const decode=(ratings:number[])=>ratings.map((rating,i)=>decodeSyncPushRequest({apiVersion:1,schemaVersion:1,mutations:[{
      mutationId:`m${i}`,entityType:'visit',entityId:`v${i}`,operation:'upsert',baseVersion:0,
      clientTimestamp:payload.updatedAt,payload:{...payload,id:`v${i}`,rating},
    }]}).mutations[0].payload as unknown as Visit)
    const legal=[...Array(8).fill(4.5),5]
    expect(buildRestaurantSummaries([restaurant],decode(legal))[0].scoreOutOfTen).toBe(9.1)
    for(const invalid of [4.55,8.8,9.1])expect(()=>decode([invalid])).toThrow()
  })
})
