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
export type ScoreBandFilter = 'all' | ScoreBand
export type QueueFilter = 'all' | QueueDuration | 'unrecorded'
export type DiningModeFilter = 'all' | DiningMode
export type DiningOccasionFilter = 'all' | DiningOccasion
export type RecommendationSourceFilter = 'all' | RecommendationSourceType
export type PriceRangeFilter = 'all' | 'under100' | '100to200' | 'over200'
export type VisitPeriodFilter = 'all' | 'sixMonths' | 'year'

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
  tag: string
  city: string
  companionOptions: string[]
  tagOptions: string[]
  cityOptions: string[]
  showVisitCount: boolean
  onVisitCountChange: (value: VisitCountFilter) => void
  onScoreBandChange: (value: ScoreBandFilter) => void
  onQueueDurationChange: (value: QueueFilter) => void
  onDiningModeChange: (value: DiningModeFilter) => void
  onDiningOccasionChange: (value: DiningOccasionFilter) => void
  onRecommendationSourceChange: (value: RecommendationSourceFilter) => void
  onPriceRangeChange: (value: PriceRangeFilter) => void
  onVisitPeriodChange: (value: VisitPeriodFilter) => void
  onCompanionChange: (value: string) => void
  onTagChange: (value: string) => void
  onCityChange: (value: string) => void
  onReset: () => void
  onClose: () => void
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
  tag,
  city,
  companionOptions,
  tagOptions,
  cityOptions,
  showVisitCount,
  onVisitCountChange,
  onScoreBandChange,
  onQueueDurationChange,
  onDiningModeChange,
  onDiningOccasionChange,
  onRecommendationSourceChange,
  onPriceRangeChange,
  onVisitPeriodChange,
  onCompanionChange,
  onTagChange,
  onCityChange,
  onReset,
  onClose,
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
        <span>评分区间</span>
        <div>
          <button className={scoreBand === 'all' ? 'is-active' : ''} onClick={() => onScoreBandChange('all')} type="button">全部</button>
          {SCORE_BAND_ORDER.map((value) => {
            const item = SCORE_BAND_META[value]
            return (
            <button className={scoreBand === value ? 'is-active' : ''} key={value} onClick={() => onScoreBandChange(value)} type="button">
              <i className="filter-color-dot" style={{ background: item.color }} />{item.label}
            </button>
            )
          })}
        </div>
      </div>
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
      <div className="filter-select-grid">
        <FilterSelect label="城市" value={city} allLabel="全部城市" options={cityOptions} onChange={onCityChange} />
        <FilterSelect label="标签 / 菜系" value={tag} allLabel="全部标签" options={tagOptions} onChange={onTagChange} />
        {showVisitCount ? (
          <FilterSelect label="饭搭子" value={companion} allLabel="全部饭搭子" options={companionOptions} onChange={onCompanionChange} />
        ) : null}
        {showVisitCount ? <FilterSelect label="用餐场景" value={diningOccasion} allLabel="全部场景" options={DINING_OCCASION_OPTIONS.map((item) => item.value)} optionLabels={Object.fromEntries(DINING_OCCASION_OPTIONS.map((item) => [item.value, item.label]))} onChange={(value) => onDiningOccasionChange(value as DiningOccasionFilter)} /> : null}
        {showVisitCount ? <FilterSelect label="推荐来源" value={recommendationSource} allLabel="全部来源" options={RECOMMENDATION_SOURCE_OPTIONS.map((item) => item.value)} optionLabels={Object.fromEntries(RECOMMENDATION_SOURCE_OPTIONS.map((item) => [item.value, item.label]))} onChange={(value) => onRecommendationSourceChange(value as RecommendationSourceFilter)} /> : null}
        {showVisitCount ? <FilterSelect label="人均价格" value={priceRange} allLabel="全部价格" options={['under100', '100to200', 'over200']} optionLabels={{ under100: '¥100 以下', '100to200': '¥100–200', over200: '¥200 以上' }} onChange={(value) => onPriceRangeChange(value as PriceRangeFilter)} /> : null}
        {showVisitCount ? <FilterSelect label="到访时间" value={visitPeriod} allLabel="不限时间" options={['sixMonths', 'year']} optionLabels={{ sixMonths: '最近半年', year: '最近一年' }} onChange={(value) => onVisitPeriodChange(value as VisitPeriodFilter)} /> : null}
      </div>
    </section>
  )
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
