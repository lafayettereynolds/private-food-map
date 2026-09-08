import { describe, expect, it } from 'vitest'
import { analyticsResultHighlights } from './analyticsResultHighlights'
import type { AnalyticsMode, AnalyticsSection } from '../services/analyticsReportTypes'

const section = (id: string): AnalyticsSection => ({ id, title: id, rows: [{ id: 'r', label: '真实结论', count: 2 }] })
describe('results-first report presentation', () => {
  it('prioritizes historical changes ahead of supporting rankings, caps at three, and does not mutate evidence', () => {
    const sections = ['top-restaurants', 'repeat', 'restaurant-roles', 'recent-history'].map(section)
    const original = structuredClone(sections)
    expect(analyticsResultHighlights('taste', sections).map(item => item.section.id)).toEqual(['recent-history', 'restaurant-roles', 'repeat'])
    expect(sections).toEqual(original)
  })
  it('never fills result cards with insufficient samples, empty rows or zero counts', () => {
    expect(analyticsResultHighlights('taste', [{ ...section('recent-history'), confidence: 'insufficient' }, { ...section('repeat'), rows: [] }, { ...section('top-restaurants'), rows: [{ id: 'zero', label: '无到访', count: 0 }] }])).toEqual([])
  })
  it('promotes the existing qualified source conclusion without inventing a winner', () => {
    const result = analyticsResultHighlights('source', [{ id: 'source-conclusions', title: '全部来源比较结论', rows: [{ id: 'most-used', label: '最常使用' }, { id: 'best', label: '最靠谱' }] }])
    expect(result[0].row.id).toBe('best')
    expect(result[0].section.title).toBe('全部来源比较结论')
  })
  it.each<AnalyticsMode>(['taste', 'companion', 'source', 'monthly', 'annual'])('keeps missing %s evidence honest', mode => {
    expect(analyticsResultHighlights(mode, [])).toEqual([])
  })
})
