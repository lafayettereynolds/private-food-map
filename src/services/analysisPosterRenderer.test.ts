import { describe, expect, it, vi } from 'vitest'
import type { AnalysisShareData } from '../types/analysisShare'
import { posterTextLines, prepareAnalysisPoster, renderAnalysisPosterSvg } from './analysisPosterRenderer'
import { posterFoodArtwork } from './posterFoodArtwork'
import { resolveFoodLibraryArtwork } from '../visuals/FoodLibraryArtwork'
import catalog from '../../public/food-library/catalog.json'

vi.mock('./posterFoodArtwork', () => ({ posterFoodArtwork: vi.fn(async () => 'data:image/png;base64,LIBRARY'), posterObjectArtwork: vi.fn(async () => 'data:image/png;base64,OBJECT'), posterPreferenceArtwork: vi.fn(async () => null) }))
vi.mock('./foodVisualResolver', () => ({ resolveVisualForPoster: vi.fn(async (visual?: { source: string | null }) => visual?.source ?? null) }))

function data(type: AnalysisShareData['type'] = 'MONTHLY_REVIEW'): AnalysisShareData {
  const image = { source: null, photoId: null, origin: 'fallback' as const, label: '未命名小店', restaurantId: 'r', tags: ['咖啡'] }
  return { reportId: 'owner:snapshot', userId: 'owner', type, title: '本月回顾', eyebrow: 'MONTHLY REVIEW', subtitle: '2026 年 9 月', summary: '本期记录了 2 次到访。', metrics: [{ label: '唯一指标', value: '2 次' }], insights: ['完整依据，包含 2 次真实到访。'], keywords: [], restaurants: [{ restaurantId: 'r', name: image.label, meta: '2 次到访', image }], heroCandidates: [image], footer: 'Taste Map · 真实记录', logoSource: '', privacy: { companionNameIncluded: false, spendIncluded: false, exactLocationIncluded: false } }
}

describe('analysis poster renderer boundaries', () => {
  it('never replaces an explicit empty data finding list with old poster-only insights', () => {
    const input = data(); input.posterFindings = []
    input.insights = ['没有通过门槛的旧结论']
    const svg = renderAnalysisPosterSvg({ data: input, hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    expect(svg).not.toContain('没有通过门槛的旧结论')
    expect(svg).toContain('记录仍在积累')
    expect(svg).toContain('这个月值得记住')
  })
  it('keeps the taste headline and scope and makes every missing chart honest', () => {
    const input = data('TASTE_PROFILE'); input.posterFindings = []
    input.tasteProfile = { periodLabel: '2026.01.01–2026.09.07', restaurantCount: 0, dishCount: 0, visitCount: 0, spend: null, cityCount: 0, averageScoreOutOfTen: null, cuisines: [], preferences: [], spendCategories: [], priceRanges: [], cities: [], companions: [], diningTimes: [], cuisineNote: '占 0 次到访；菜系可多选，占比不相加', diningTimeNote: '0/0 次有用餐时刻；按当前时区统计' }
    const ranked = renderAnalysisPosterSvg({ data: input, hero: null, logo: null, restaurantImages: ['data:image/png;base64,TEST'], heroIndex: 0 })
    expect(ranked).toContain('x="81" y="764" width="62" height="62"')
    expect(ranked).toContain('<circle cx="112" cy="795" r="31"/>')
    // Rank ends at x=68; artwork starts at x=81, preserving a 13px gap.
    expect(ranked).toContain('<circle cx="53" cy="795" r="15"')
    expect(ranked).toContain('<text x="154" y="781"')
    input.restaurants = []
    const svg = renderAnalysisPosterSvg({ data: input, hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    expect(svg).toContain('data-poster-headline')
    expect(svg).toContain('data-poster-cuisine-scope')
    expect(svg).toContain('到访平均评分')
    expect(svg).toContain('尚无餐厅到访记录')
    expect(svg).toContain('尚无可分析的用餐时刻')
    expect(svg).toContain('完整记录保留在数据版')
    expect(svg).not.toContain('>消费占比</text>')
  })
  it('uses restaurant tags for both supplied-library hero and evidence, keeping provenance explicit', async () => {
    const prepared = await prepareAnalysisPoster(data())
    expect(posterFoodArtwork).toHaveBeenCalledWith('未命名小店', ['咖啡'])
    expect(prepared).toMatchObject({ heroIsIllustration: true, restaurantIllustrations: [true] })
    const svg = renderAnalysisPosterSvg(prepared)
    expect(svg).toContain('食物素材插画 · 非餐厅实拍')
    expect(svg).toContain('素材插画 · 非实拍')
  })
  it('does not repeat one metric to fill six decorative positions', () => {
    const svg = renderAnalysisPosterSvg({ data: data(), hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    expect(svg.match(/唯一指标/g)).toHaveLength(1)
  })
  it('preserves graphemes, XML safety and explicit paragraph boundaries', () => {
    expect(posterTextLines('👩🏽‍🍳厨房\nA&B <test>', 60, 20).join('')).toBe('👩🏽‍🍳厨房A&B <test>')
    expect(posterTextLines('👩🏽‍🍳厨房', 20, 20)[0]).toBe('👩🏽‍🍳')
    const input = data(); input.title = 'A&B <test>'
    expect(renderAnalysisPosterSvg({ data: input, hero: null, logo: null, restaurantImages: [], heroIndex: 0 })).toContain('A&amp;B &lt;test&gt;')
  })
  it('labels all-source comparison separately from selected-source evidence, including absent baseline', () => {
    const input = data('RECOMMENDATION_SOURCE')
    input.sourceResults = { baseline: null, baselineCount: 0, best: null, worst: { name: '另一来源', rate: 1, count: 5, outcomeCount: 5, average: 2 } }
    const svg = renderAnalysisPosterSvg({ data: input, hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    expect(svg).toContain('全部来源比较')
    expect(svg).toContain('当前所选来源 · 代表餐厅')
    expect(svg).not.toContain('让我踩坑的店')
    expect(svg).not.toContain('未评分 / 10')
  })
  it('uses all five meal periods and all seven real price ranges instead of silently dropping late meals or expensive meals', () => {
    const input = data('TASTE_PROFILE'); input.privacy.spendIncluded = true
    input.tasteProfile = { periodLabel: '2026', restaurantCount: 1, dishCount: 1, visitCount: 1, spend: 800, cityCount: 1, averageScoreOutOfTen: null,
      cuisines: [], preferences: [], spendCategories: [], priceRanges: [0, 50, 100, 200, 300, 500, 800].map(value => ({ label: `¥${value}+`, value: value === 800 ? 100 : 0, symbol: '' })), cities: [], companions: [], diningTimes: ['早餐', '午餐', '下午茶', '晚餐', '夜宵'].map(label => ({ label, value: label === '夜宵' ? 100 : 0, symbol: '' })) }
    const svg = renderAnalysisPosterSvg({ data: input, hero: null, logo: null, restaurantImages: [], heroIndex: 0 })
    expect(svg).toContain('夜宵'); expect(svg).toContain('¥800+')
    expect(svg).toContain('未评分'); expect(svg).toContain('同行信息未分享')
    expect(svg).not.toContain('Apple Color Emoji')
  })
  it('matches generic noodle classification and excludes the next-row hotpot from Chinese art', () => {
    expect(resolveFoodLibraryArtwork({ name: '', tags: ['面条'] }).id).toBe('beef-noodles')
    expect(catalog.crops.chinese).toEqual([8, 560, 270, 222])
    expect(catalog.crops.chinese[1] + catalog.crops.chinese[3]).toBeLessThan(catalog.crops.hotpot[1])
    expect(catalog.crops.seafood).toEqual([560, 302, 266, 232])
    expect(catalog.crops.seafood[0] + catalog.crops.seafood[2]).toBeLessThan(836)
  })
  it('keeps taste 2:3, uses object artwork, preserves actual Top3 scores and forbids fake geographic points', async () => {
    const input = data('TASTE_PROFILE')
    input.restaurants[0].score = '8.6'
    input.tasteProfile = { periodLabel: '2026', restaurantCount: 1, dishCount: 2, visitCount: 3, spend: null, cityCount: 1, averageScoreOutOfTen: 8.6,
      cuisines: [], preferences: [{ label: '清淡', value: 30, symbol: '' }], spendCategories: [], priceRanges: [], cities: [{ label: '杭州', value: 1, symbol: '' }], companions: [], diningTimes: [{ label: '夜宵', value: 100, symbol: '' }] }
    const prepared = await prepareAnalysisPoster(input)
    prepared.preferenceArtwork = ['data:image/png;base64,LEAF']
    const svg = renderAnalysisPosterSvg(prepared)
    expect(svg).toContain('width="1080" height="1620"')
    expect(svg.match(/data-poster-overview-icon=/g)).toHaveLength(3)
    expect(svg).toContain('data-poster-top-score="0"')
    expect(svg).toContain('data-poster-preference-art="清淡"')
    expect(svg).toContain('地图插画 · 非真实定位')
    expect(svg).not.toContain('M792 1120 C840')
    expect(svg).not.toContain('cx="842" cy="1206"')
    expect(svg).not.toContain('cy="1426" r="18"')
    expect(svg).not.toContain('cy="855" r="18"')
    expect(svg).toContain('消费详情未分享')
    expect(svg).toContain('夜宵')
    expect(svg).toContain('100%')
  })
})
