import {
  DINING_MODE_OPTIONS,
  DINING_OCCASION_OPTIONS,
  QUEUE_DURATION_OPTIONS,
  RECOMMENDATION_SOURCE_OPTIONS,
  SCORE_BAND_META,
  SCORE_BAND_ORDER,
  type DiningMode,
  type DiningOccasion,
  type QueueDuration,
  type RecommendationSourceType,
  type ScoreBand,
} from '../types/domain'

export type VisitCountFilter = 'all' | '1' | '2' | '3' | '5' | '10'
export type ScoreBandFilter = ScoreBand[]
export type QueueFilter = 'all' | QueueDuration | 'unrecorded'
export type DiningModeFilter = 'all' | DiningMode
export type DiningOccasionFilter = 'all' | DiningOccasion
export type RecommendationSourceFilter = 'all' | RecommendationSourceType
export type PriceRangeFilter = 'all' | 'under100' | '100to200' | 'over200'
export type VisitPeriodFilter = 'all' | 'sixMonths' | 'year'
export type RecommendationDistanceFilter = 'all' | '1' | '3' | '5' | '10'
export type RecommendationSortFilter = 'recommended' | 'nearest' | 'rating'

interface RestaurantFiltersProps {
  visitCount: VisitCountFilter
  scoreBand: ScoreBandFilter
  queueDuration: QueueFilter
  diningMode: DiningModeFilter
  diningOccasion: DiningOccasionFilter
  recommendationSource: RecommendationSourceFilter
  priceRange: PriceRangeFilter
  visitPeriod: VisitPeriodFilter
  companion: string
  city: string
  companionOptions: string[]
  cityOptions: string[]
  showVisitCount: boolean
  isRecommendation?: boolean
  recommendationDistance?: RecommendationDistanceFilter
  recommendationSort?: RecommendationSortFilter
  recommendationLocationStatus?: 'idle' | 'loading' | 'ready' | 'error'
  recommendationLocationLabel?: string
  onVisitCountChange: (value: VisitCountFilter) => void
  onScoreBandChange: (value: ScoreBandFilter) => void
  onQueueDurationChange: (value: QueueFilter) => void
  onDiningModeChange: (value: DiningModeFilter) => void
  onDiningOccasionChange: (value: DiningOccasionFilter) => void
  onRecommendationSourceChange: (value: RecommendationSourceFilter) => void
  onPriceRangeChange: (value: PriceRangeFilter) => void
  onVisitPeriodChange: (value: VisitPeriodFilter) => void
  onCompanionChange: (value: string) => void
  onCityChange: (value: string) => void
  onReset: () => void
  onClose: () => void
  onRecommendationDistanceChange?: (value: RecommendationDistanceFilter) => void
  onRecommendationSortChange?: (value: RecommendationSortFilter) => void
}

export function RestaurantFilters({
  visitCount,
  scoreBand,
  queueDuration,
  diningMode,
  diningOccasion,
  recommendationSource,
  priceRange,
  visitPeriod,
  companion,
  city,
  companionOptions,
  cityOptions,
  showVisitCount,
  isRecommendation = false,
  recommendationDistance = 'all',
  recommendationSort = 'recommended',
  recommendationLocationStatus = 'idle',
  recommendationLocationLabel = '已按当前位置计算距离',
  onVisitCountChange,
  onScoreBandChange,
  onQueueDurationChange,
  onDiningModeChange,
  onDiningOccasionChange,
  onRecommendationSourceChange,
  onPriceRangeChange,
  onVisitPeriodChange,
  onCompanionChange,
  onCityChange,
  onReset,
  onClose,
  onRecommendationDistanceChange,
  onRecommendationSortChange,
}: RestaurantFiltersProps) {
  return (
    <section className="filters-panel">
      <header>
        <strong>筛选餐厅</strong>
        <div className="filters-panel__actions">
          <button onClick={onReset} type="button">重置</button>
          <button className="filters-panel__done" onClick={onClose} type="button">完成</button>
        </div>
      </header>
      {showVisitCount ? (
        <div className="filter-group">
          <span>用餐方式</span>
          <div>
            <button className={diningMode === 'all' ? 'is-active' : ''} onClick={() => onDiningModeChange('all')} type="button">全部</button>
            {DINING_MODE_OPTIONS.map((option) => <button className={diningMode === option.value ? 'is-active' : ''} key={option.value} onClick={() => onDiningModeChange(option.value)} type="button">{option.label}</button>)}
          </div>
        </div>
      ) : null}
      {showVisitCount ? (
        <div className="filter-group">
          <span>到访次数</span>
          <div>
            {([
              ['all', '全部'],
              ['1', '1+'],
              ['2', '2+'],
              ['3', '3+'],
              ['5', '5+'],
              ['10', '10+'],
            ] as [VisitCountFilter, string][]).map(([value, label]) => (
              <button className={visitCount === value ? 'is-active' : ''} key={value} onClick={() => onVisitCountChange(value)} type="button">{label}</button>
            ))}
          </div>
        </div>
      ) : null}
      <div className="filter-group">
        <span>评分区间 · 可多选</span>
        <div>
          <button className={!scoreBand.length ? 'is-active' : ''} onClick={() => onScoreBandChange([])} type="button">全部</button>
          {SCORE_BAND_ORDER.map((value) => {
            const item = SCORE_BAND_META[value]
            return (
            <button className={scoreBand.includes(value) ? 'is-active' : ''} key={value} onClick={() => onScoreBandChange(scoreBand.includes(value) ? scoreBand.filter((item) => item !== value) : [...scoreBand, value])} type="button">
              <i className="filter-color-dot" style={{ background: item.color }} />{item.label}
            </button>
            )
          })}
        </div>
      </div>
      {isRecommendation ? <div className="filter-group">
        <span>距离</span>
        <div>
          {([['all', '不限'], ['1', '1 km 内'], ['3', '3 km 内'], ['5', '5 km 内'], ['10', '10 km 内']] as const).map(([value, label]) => <button className={recommendationDistance === value ? 'is-active' : ''} key={value} onClick={() => onRecommendationDistanceChange?.(value)} type="button">{label}</button>)}
        </div>
      </div> : null}
      {showVisitCount ? (
        <div className="filter-group">
          <span>等待时长</span>
          <div>
            <button className={queueDuration === 'all' ? 'is-active' : ''} onClick={() => onQueueDurationChange('all')} type="button">全部</button>
            {QUEUE_DURATION_OPTIONS.map((option) => (
              <button className={queueDuration === option.value ? 'is-active' : ''} key={option.value} onClick={() => onQueueDurationChange(option.value)} type="button">{option.label}</button>
            ))}
            <button className={queueDuration === 'unrecorded' ? 'is-active' : ''} onClick={() => onQueueDurationChange('unrecorded')} type="button">未记录</button>
          </div>
        </div>
      ) : null}
      {showVisitCount ? <FilterChoices label="适合场景" value={diningOccasion} options={DINING_OCCASION_OPTIONS} onChange={(value) => onDiningOccasionChange(value as DiningOccasionFilter)} /> : null}
      {showVisitCount ? <FilterChoices label="推荐来源" value={recommendationSource} options={RECOMMENDATION_SOURCE_OPTIONS.map((item) => item.value === 'other' ? { ...item, label: '自定义' } : item)} onChange={(value) => onRecommendationSourceChange(value as RecommendationSourceFilter)} /> : null}
      {showVisitCount ? <FilterChoices label="人均价格" value={priceRange} options={[{ value: 'under100', label: '¥100 以下' }, { value: '100to200', label: '¥100–200' }, { value: 'over200', label: '¥200 以上' }]} onChange={(value) => onPriceRangeChange(value as PriceRangeFilter)} /> : null}
      {showVisitCount ? <FilterChoices label="到访时间" value={visitPeriod} allLabel="不限" options={[{ value: 'sixMonths', label: '最近半年' }, { value: 'year', label: '最近一年' }]} onChange={(value) => onVisitPeriodChange(value as VisitPeriodFilter)} /> : null}
      <div className="filter-select-grid">
        {isRecommendation ? <label><span>排序</span><select aria-label="推荐排序" onChange={(event) => onRecommendationSortChange?.(event.target.value as RecommendationSortFilter)} value={recommendationSort}><option value="recommended">综合推荐</option><option value="nearest">距离最近</option><option value="rating">评分最高</option></select></label> : null}
        <FilterSelect label="城市" value={city} allLabel="全部城市" options={cityOptions} onChange={onCityChange} />
        {showVisitCount ? (
          <FilterSelect label="饭搭子" value={companion} allLabel="全部饭搭子" options={companionOptions} onChange={onCompanionChange} />
        ) : null}
      </div>
      {isRecommendation && (recommendationDistance !== 'all' || recommendationSort === 'nearest') ? <p className={`recommendation-filter-location is-${recommendationLocationStatus}`}>{recommendationLocationStatus === 'loading' ? '正在确定距离基准…' : recommendationLocationStatus === 'ready' ? recommendationLocationLabel : recommendationLocationStatus === 'error' ? '无法取得位置，距离条件暂未生效' : ''}</p> : null}
    </section>
  )
}

function FilterChoices({ label, value, options, onChange, allLabel = '全部' }: { label: string; value: string; options: ReadonlyArray<{ value: string; label: string }>; onChange: (value: string) => void; allLabel?: string }) {
  return <div className="filter-group"><span>{label}</span><div><button className={value === 'all' ? 'is-active' : ''} onClick={() => onChange('all')} type="button">{allLabel}</button>{options.map((option) => <button className={value === option.value ? 'is-active' : ''} key={option.value} onClick={() => onChange(option.value)} type="button">{option.label}</button>)}</div></div>
}

function FilterSelect({
  label,
  value,
  allLabel,
  options,
  optionLabels,
  onChange,
}: {
  label: string
  value: string
  allLabel: string
  options: string[]
  optionLabels?: Record<string, string>
  onChange: (value: string) => void
}) {
  return (
    <label>
      <span>{label}</span>
      <select aria-label={`按${label}筛选`} onChange={(event) => onChange(event.target.value)} value={value}>
        <option value="all">{allLabel}</option>
        {options.map((item) => <option key={item} value={item}>{optionLabels?.[item] ?? item}</option>)}
      </select>
    </label>
  )
}
