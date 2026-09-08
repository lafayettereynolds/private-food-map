import { renderToStaticMarkup } from 'react-dom/server'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { TasteMapRecommendationReasons, TasteMapRecommendationSignal } from './TasteMapDiscoveryShared'
import { scoreColor } from '../types/domain'
import type { CalibratedLikeProbability } from '../contracts/recommendationSignal'
import nativeTheme from '../../ios/TasteMap/TasteMap/Components/TasteMapCoreTheme.swift?raw'

afterEach(() => vi.useRealTimers())

describe('recommendation percentage uses the existing ten-point score palette', () => {
  it.each([0, 10, 20, 29, 30, 49, 50, 69, 70, 80, 88, 89, 90, 95, 100])('%s percent maps to percent / 10 without changing signal meaning', percent => {
    const html = renderToStaticMarkup(<TasteMapRecommendationSignal input={{ personalTastePercent: percent }} />)
    expect(html).toContain(`--tm-taste-prediction-color:${scoreColor(percent / 10)}`)
    expect(html).toContain(`${percent}%`)
    expect(html).toContain('data-recommendation-signal="match"')
    expect(html).toContain('口味匹配度')
    expect(html).toContain('data-signal-artwork="ribbon-medal"')
    expect(html).toContain('class="tm-recommendation-ribbon"')
  })

  it('uses the same palette for a validated probability while preserving its distinct label and mode', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-09-06T00:00:00Z'))
    const probability: CalibratedLikeProbability = {
      value: .9, modelVersion: 'test-model', calibrationVersion: 'test-calibration',
      calibrationStatus: 'validated', evidenceStatus: 'sufficient',
      positiveFeedbackDefinition: '测试中的明确喜欢反馈', definitionVersion: 'test-v1',
      definitionStatus: 'approved', validationSampleCount: 800, validUntil: '2026-09-07T00:00:00Z',
    }
    const html = renderToStaticMarkup(<TasteMapRecommendationSignal input={{ personalTastePercent: 50, calibratedLikeProbability: probability }} />)
    expect(html).toContain(`--tm-taste-prediction-color:${scoreColor(9)}`)
    expect(html).toContain('data-recommendation-signal="probability"')
    expect(html).toContain('喜欢概率')
    expect(html).toContain('90%')
  })

  it.each([undefined, null, -1, 101, NaN])('missing or invalid evidence stays neutral, not a zero-score color (%s)', percent => {
    const html = renderToStaticMarkup(<TasteMapRecommendationSignal input={{ personalTastePercent: percent }} />)
    expect(html).toContain(`--tm-taste-prediction-color:${scoreColor(null)}`)
    expect(html).toContain('积累中')
  })

  it('keeps Native on the same score policy and ribbon artwork, never the old dashed signal circle', () => {
    const signal = nativeTheme.split('struct TasteMapRecommendationSignalView: View {')[1].split('struct TasteMapSectionHeader: View {')[0]
    expect(signal).toContain('RestaurantScoreColorPolicy.color(forTenPointScore: percent.map { $0 / 10 })')
    expect(signal).toContain('TasteMapRecommendationMedalArtwork(accent: signalColor, value: value, label: label)')
    expect(signal).not.toContain('recommendationMatchDash : []')
    expect(signal).not.toContain('.foregroundStyle(TasteMapCoreTheme.brandDeep)')
  })

  it('keeps methodology behind the badge, not in the feed by default', () => {
    const html = renderToStaticMarkup(<TasteMapRecommendationSignal input={{ personalTastePercent: 88 }} />)
    expect(html).not.toContain('不代表喜欢这家餐厅的概率')
    expect(html).toContain('aria-haspopup="dialog"')
    expect(html).toContain('class="tm-recommendation-ribbon__percent"')
    expect(html).toContain('class="tm-recommendation-ribbon__label"')
  })

  it('renders all complete supplied reasons directly, deduplicating only exact repeated text', () => {
    const reasons = ['与你去过的「桂雨咖啡 7」相似 88%，同时包含完整的餐厅名称', '你经常选择这一类菜系', '在你最近记录的消费区间内']
    const html = renderToStaticMarkup(<TasteMapRecommendationReasons reasons={[...reasons, reasons[0], ' ']} />)
    reasons.forEach(reason => expect(html).toContain(`<li>${reason}</li>`))
    expect(html.match(/<li>/g)).toHaveLength(3)
    expect(html).not.toContain('aria-hidden')
    expect(html).not.toContain('<button')
    expect(html).not.toContain('…')
    const nativeReasons = nativeTheme.split('struct TasteMapRecommendationReasons: View {')[1].split('private struct TasteMapEvidenceFlowLayout')[0]
    expect(nativeReasons).toContain('Text(reason)')
    expect(nativeReasons).not.toContain('.lineLimit(1)')
    expect(nativeReasons).not.toContain('prefix(12)')
  })
})
