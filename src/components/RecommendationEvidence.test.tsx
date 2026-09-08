import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { distinctRecommendationReasons, RecommendationEvidence, RecommendationEvidenceBody, type RecommendationEvidenceItem } from './RecommendationEvidence'

const base: RecommendationEvidenceItem = {
  id: 'evidence-test', mode: 'for_you', reason: '', reasons: [], sourceUser: null,
  restaurant: { id: 'restaurant-test', name: '依据测试餐厅', address: '', city: '杭州', tags: [], latitude: 0, longitude: 0, referencePrice: null, image: { kind: 'foodDiningFallback', stableSeed: 'test', accessibilityLabel: '无图片' } },
}
const body = (item: RecommendationEvidenceItem) => renderToStaticMarkup(<RecommendationEvidenceBody item={item} />)

describe('recommendation evidence disclosure', () => {
  it('renders supplied private participants and marks incomplete records without inventing them', () => {
    const html = body({ ...base, reasons: [{ code: 'INITIAL_HISTORY_MATCH', text: '初步匹配', evidence: {
      sampleCount: 1, source: 'owner_history', participantCount: 1, missingFields: ['complete_visit_list'], participants: [{
        restaurantID: 'canonical-1', restaurantName: '真实参照店', restaurantRecordIDs: ['restaurant-1'], visitIDs: ['visit-1'],
        fields: { tags: ['日料'], ratingCount: 2, meanOutOfTen: 8, referenceRatingOutOfTen: 8, visitCount: 2,
          firstVisitedAt: '2026-01-01', lastVisitedAt: '2026-02-01', recordedPricePerPerson: null, priceCurrency: null },
      }],
    } }] })
    expect(html).toContain('真实参照店')
    expect(html).toContain('8.0 / 10')
    expect(html).toContain('visit-1')
    expect(html).toContain('完整逐次到访清单')
    expect(html).not.toContain('visit-2')
  })
  it('shows at most three complete distinct semantic reasons, without fillers', () => {
    const item = { ...base, reasons: [{ code: 'A', text: '第一条完整理由' }, { code: 'A', text: '同一种理由的第二种说法' }, { code: 'B', text: '第二条' }, { code: 'C', text: '第三条' }, { code: 'D', text: '第四条' }] }
    expect(distinctRecommendationReasons(item).map(reason => reason.text)).toEqual(['第一条完整理由', '第二条', '第三条'])
    const html = renderToStaticMarkup(<RecommendationEvidence item={item} />)
    expect(html).toContain('第一条完整理由')
    expect(html).not.toContain('查看依据')
    expect(html).not.toContain('<button')
    expect(html).not.toContain('第四条')
    expect(html).not.toContain('role="dialog"')
  })
  it('does not manufacture reasons or a button for missing evidence', () => {
    expect(renderToStaticMarkup(<RecommendationEvidence item={base} />)).toBe('')
    expect(body({ ...base, reason: '旧接口提供的原始理由' })).toContain('尚未提供样本与记录明细')
  })
  it('keeps known zero exploration samples distinct from unknown counts', () => {
    const html = body({ ...base, reasons: [{ code: 'SHORT_TERM_DIVERSITY', text: '可以探索', evidence: { sampleCount: 0, windowDays: 365 } }] })
    expect(html).toContain('0 家')
    expect(html).toContain('过去 365 天')
    expect(html).toContain('尚未提供逐店、逐次到访明细')
    expect(body({ ...base, reasons: [{ code: 'HIGH_CUISINE_MATCH', text: '原始理由', evidence: { sampleCount: NaN, meanOutOfTen: 12 } }] })).toContain('未提供有效评分')
  })
  it('shows only supplied matched fields and rating without parsing reason text', () => {
    const html = body({ ...base, reasons: [{ code: 'TASTE_TAG_MATCH', text: '与你给过9分的「参考店」接近', evidence: { sampleCount: 1, dimensions: ['餐厅类型', '人均消费', '餐厅类型'], referenceRestaurantID: 'reference' } }] })
    expect(html).toContain('餐厅类型、人均消费')
    expect(html).toContain('未提供起止时间')
    expect(html).not.toContain('样本平均评分')
    expect(html).not.toContain('共同评分')
  })
  it('renders viewer-visible actual visit ratings, not an invented average/probability', () => {
    const user = { userId: 'user-1', displayName: '<访客>', bio: null, city: null, avatarPhotoId: null, avatarPresetId: 'cat', friendshipId: null, friendshipState: 'none', isFollowing: false } as const
    const record = { user, visitId: 'visit-1', visitedAt: '2026-09-07T00:10:00+08:00', rating: 4.25 }
    const html = body({ ...base, mode: 'similar_taste', reasons: [{ code: 'SIMILAR_USERS', text: '原始同味理由' }], tasteEvidence: { evidenceState: 'forming', sharedRestaurantCount: 5, supporterCount: 2, aggregation: 'equal_user_mean', latestVisibleVisitAt: record.visitedAt, records: [record, record, { ...record, visitId: 'visit-2', rating: null, visitedAt: 'invalid' }] } })
    expect(html).toContain('样本仍在积累')
    expect(html).toContain('5 家')
    expect(html).toContain('2 人')
    expect(html).toContain('不是所有用户的合计')
    expect(html).toContain('8.5 / 10')
    expect(html.match(/8.5 \/ 10/g)).toHaveLength(1)
    expect(html).toContain('2026年9月7日')
    expect(html).toContain('未提供有效日期')
    expect(html).toContain('未提供有效评分')
    expect(html).toContain('&lt;访客&gt;')
    expect(html).not.toContain('0.0 / 10')
    expect(html).not.toContain('%')
  })
  it('labels missing Similar Taste record provenance without claiming zero supporters', () => {
    const html = body({ ...base, mode: 'similar_taste' })
    expect(html).toContain('尚未提供共同评分样本')
    expect(html).not.toContain('0 人')
  })
})
