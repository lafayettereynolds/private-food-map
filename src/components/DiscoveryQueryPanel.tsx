import { useState } from 'react'
import { DISCOVERY_RATING_FILTER_THRESHOLDS, minimumRatingFilterLabel } from '../utils/ratingFilterOptions'
import { ModalShell } from './ModalShell'
import { normalizeDiscoveryFilters, type NormalizedDiscoveryFilters } from '../contracts/discoveryFilters'
import { DISCOVERY_FILTER_TAXONOMY } from '../contracts/discoveryFilterTaxonomy'
import { normalizeDiscoverySessionPreferences, type DiscoverySessionPreferences } from '../contracts/discoverySessionPreferences'
import type { TasteMapPlatform, TasteMapDiscoveryCityPageRequest } from '../platform/TasteMapPlatform'
import './discoveryQueryPanel.css'

export interface DiscoveryQueryDraft {
  city: string
  filters: NormalizedDiscoveryFilters
  sort: NonNullable<TasteMapDiscoveryCityPageRequest['sort']>
  windowDays: 7 | 30
  preferences: DiscoverySessionPreferences
}
export function DiscoveryQueryPanel({ initial, mode, platform, onCancel, onApply }: {
  initial: DiscoveryQueryDraft; mode: string; platform: TasteMapPlatform
  onCancel: () => void; onApply: (value: DiscoveryQueryDraft) => void
}) {
  const [draft, setDraft] = useState(() => structuredClone(initial))
  const [error, setError] = useState('')
  const [locating, setLocating] = useState(false)
  const personalized = mode === 'for_you' || mode === 'similar_taste'
  const filters = (change: Partial<NormalizedDiscoveryFilters>) => setDraft(value => ({ ...value, filters: { ...value.filters, ...change } }))
  const preferences = (change: Partial<DiscoverySessionPreferences>) => setDraft(value => ({ ...value, preferences: { ...value.preferences, ...change } }))
  async function locate(radius?: number) {
    setLocating(true); setError('')
    try {
      const location = await platform.location.current()
      if (location.authorizationStatus !== 'allowed' || !Number.isFinite(location.latitude) || !Number.isFinite(location.longitude)
        || !Number.isFinite(Date.parse(location.timestamp)) || Math.abs(Date.now() - Date.parse(location.timestamp)) > 300_000) throw new Error('当前定位不可用，请开启定位后重试；不会用城市中心替代。')
      const reference = { latitude: location.latitude, longitude: location.longitude, source: 'device_location' as const }
      setDraft(value => ({ ...value,
        filters: radius ? { ...value.filters, distance: { maximumMeters: radius, reference } } : value.filters,
        preferences: radius ? value.preferences : { ...value.preferences, nearby: true, reference },
      }))
    } catch (cause) { setError(cause instanceof Error ? cause.message : '定位失败，请重试。') }
    finally { setLocating(false) }
  }
  const sortOptions = mode === 'for_you' ? [['recommended', '综合推荐'], ['taste', '口味匹配优先'], ['public_rating', '大家评分优先'], ['distance', '距离优先']]
    : mode === 'similar_taste' ? [['recommended', '同味推荐'], ['similar_rating', '同味评分优先'], ['distance', '距离优先']]
    : mode === 'trending' ? [['trend', '趋势排序']] : [['latest', '最新公开优先']]
  return <ModalShell title="发现筛选" eyebrow={null} size="small" onClose={onCancel}>
    <div className="sticky-action-form">
    <div className="tm-discovery-query-fields sticky-action-form__content">
      <label>搜索城市<input aria-label="筛选城市" value={draft.city} maxLength={80} onChange={event => {
        const city = event.target.value
        setDraft(value => ({ ...value, city, filters: { ...value.filters, distance: null }, preferences: { ...value.preferences, nearby: false, reference: null } }))
      }} placeholder="输入要探索的城市" /></label>
      {draft.city !== initial.city && (initial.filters.distance || initial.preferences.nearby) ? <p role="status">切换城市后将清除原来的附近范围；其他条件保留。</p> : null}
      <label>排序<select aria-label="筛选排序" value={draft.sort} onChange={event => setDraft(value => ({ ...value, sort: event.target.value as DiscoveryQueryDraft['sort'] }))}>{sortOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      {(['cuisines', 'types'] as const).map(field => <fieldset key={field}><legend>{field === 'cuisines' ? '菜系' : '餐饮类型'}（可多选）</legend><div className="tm-discovery-query-options">{DISCOVERY_FILTER_TAXONOMY[field]?.map(value => <label key={value}><input type="checkbox" checked={draft.filters[field].includes(value)} onChange={event => filters({ [field]: event.target.checked ? [...draft.filters[field], value] : draft.filters[field].filter(item => item !== value) })} />{value}</label>)}</div></fieldset>)}
      <label>大家评分<select aria-label="大家评分" value={draft.filters.minimumPublicScoreOutOfTen ?? ''} onChange={event => filters({ minimumPublicScoreOutOfTen: event.target.value ? Number(event.target.value) : null })}><option value="">不限评分</option>{DISCOVERY_RATING_FILTER_THRESHOLDS.map(value => <option key={value} value={value}>{minimumRatingFilterLabel(value)}</option>)}</select></label>
      <label>评价人数<select aria-label="评价人数" value={draft.filters.minimumPublicRatingUsers ?? ''} onChange={event => filters({ minimumPublicRatingUsers: event.target.value ? Number(event.target.value) : null })}><option value="">不限</option>{[3, 5, 10, 30].map(value => <option key={value} value={value}>至少 {value} 人</option>)}</select></label>
      <label>我的记录状态<select aria-label="我的记录状态" value={draft.filters.viewerStates[0] ?? ''} onChange={event => filters({ viewerStates: event.target.value ? [event.target.value as 'none' | 'visited' | 'want_to_go'] : [] })}><option value="">全部</option><option value="none">未去过</option><option value="want_to_go">想吃</option><option value="visited">已去过</option></select></label>
      <label><input type="checkbox" checked={draft.filters.requireActualPhoto} onChange={event => filters({ requireActualPhoto: event.target.checked })} />仅有实拍</label>
      <label>距离<select aria-label="距离" disabled={locating} value={draft.filters.distance?.maximumMeters ?? ''} onChange={event => event.target.value ? void locate(Number(event.target.value)) : filters({ distance: null })}><option value="">不限</option>{[500, 1000, 3000, 5000, 10000].map(value => <option key={value} value={value}>{value < 1000 ? '500 米' : `${value / 1000} 公里`}以内</option>)}</select></label>
      <p>距离以本次授权获得的当前位置为准。</p>
      <label>参考人均（人民币，严格限定）<select aria-label="参考人均" value={draft.filters.priceRange?.minimum ?? ''} onChange={event => {
        const minimum = event.target.value === '' ? null : Number(event.target.value)
        const bounds: Record<number, number | null> = { 0: 50, 50: 100, 100: 200, 200: 400, 400: null }
        filters({ priceRange: minimum === null ? null : { minimum, maximumExclusive: bounds[minimum], currency: 'CNY', basis: 'reference_per_person' } })
      }}><option value="">不限</option>{[[0, '50 以下'], [50, '50–100'], [100, '100–200'], [200, '200–400'], [400, '400 以上']].map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <p>限定参考人均时，不包含未知价格。旧金额统一按人民币处理。</p>
      <p>行政区域暂缺可靠归属资料，当前不能应用。</p>
      {mode === 'trending' ? <label>趋势时间<select value={draft.windowDays} onChange={event => setDraft(value => ({ ...value, windowDays: Number(event.target.value) as 7 | 30 }))}><option value="7">近 7 天</option><option value="30">近 30 天</option></select></label> : null}
      {personalized ? <fieldset><legend>本次偏好</legend><p>只调整本次排序，不修改长期口味档案。</p>
        <label>探索程度<select value={draft.preferences.exploration} onChange={event => preferences({ exploration: event.target.value as DiscoverySessionPreferences['exploration'] })}><option value="familiar">熟悉优先</option><option value="balanced">平衡</option><option value="adventurous">多点新鲜</option></select></label>
        <label>本次预算（人民币，优先而非限定）<select value={draft.preferences.budget?.minimum ?? ''} onChange={event => {
          const minimum = event.target.value === '' ? null : Number(event.target.value)
          const bounds: Record<number, number | null> = { 0: 50, 50: 100, 100: 200, 200: 400, 400: null }
          preferences({ budget: minimum === null ? null : { minimum, maximumExclusive: bounds[minimum], currency: 'CNY' } })
        }}><option value="">不限</option>{[[0, '50 以下'], [50, '50–100'], [100, '100–200'], [200, '200–400'], [400, '400 以上']].map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <p>只在有可靠、同币种人均资料时优先匹配；未知价格仍可出现。</p>
        <label>用餐情境<select value={draft.preferences.occasion} onChange={event => preferences({ occasion: event.target.value as DiscoverySessionPreferences['occasion'] })}><option value="any">不限</option><option value="solo">独自用餐</option><option value="two">两人</option><option value="group">多人聚餐</option></select></label><p>仅在餐厅有可靠场景资料时参与排序，不从饭搭子人数推测。</p>
        <label><input type="checkbox" checked={draft.preferences.nearby} disabled={locating} onChange={event => event.target.checked ? void locate() : preferences({ nearby: false, reference: null })} />附近优先</label>
      </fieldset> : null}
      {locating ? <p role="status">正在获取当前位置…</p> : null}{error ? <p role="alert">{error}</p> : null}
    </div>
    <div className="sticky-form-action-bar"><div className="modal-actions tm-discovery-query-actions"><button type="button" className="secondary-button" disabled={locating} onClick={() => {
      setError('')
      setDraft({ city: initial.city, filters: normalizeDiscoveryFilters(), sort: sortOptions[0][0] as DiscoveryQueryDraft['sort'], windowDays: 7, preferences: normalizeDiscoverySessionPreferences() })
    }}>重置</button><button type="button" className="secondary-button" onClick={onCancel}>取消</button><button type="button" className="primary-button" disabled={locating} onClick={() => {
      if (!draft.city.trim()) { setError('请先选择一个城市。'); return }
      if (draft.sort === 'distance' && !draft.filters.distance) { setError('距离排序需要先选择距离范围并获取当前位置。'); return }
      onApply({ ...draft, city: draft.city.trim(), filters: normalizeDiscoveryFilters(draft.filters, DISCOVERY_FILTER_TAXONOMY), preferences: normalizeDiscoverySessionPreferences(draft.preferences) })
    }}>应用</button></div></div>
    </div>
  </ModalShell>
}
