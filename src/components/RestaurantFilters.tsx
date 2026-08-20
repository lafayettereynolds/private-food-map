import {
  PREFERENCE_META,
  QUEUE_DURATION_OPTIONS,
  type PreferenceLevel,
  type QueueDuration,
} from '../types/domain'

export type VisitCountFilter = 'all' | '1' | '2' | '3' | '5' | '10'
export type RatingFilter = 'all' | '9' | '8' | '7' | 'unrated'
export type PreferenceFilter = 'all' | PreferenceLevel
export type QueueFilter = 'all' | QueueDuration | 'unrecorded'

interface RestaurantFiltersProps {
  visitCount: VisitCountFilter
  rating: RatingFilter
  preference: PreferenceFilter
  queueDuration: QueueFilter
  companion: string
  tag: string
  city: string
  companionOptions: string[]
  tagOptions: string[]
  cityOptions: string[]
  showVisitCount: boolean
  onVisitCountChange: (value: VisitCountFilter) => void
  onRatingChange: (value: RatingFilter) => void
  onPreferenceChange: (value: PreferenceFilter) => void
  onQueueDurationChange: (value: QueueFilter) => void
  onCompanionChange: (value: string) => void
  onTagChange: (value: string) => void
  onCityChange: (value: string) => void
  onReset: () => void
}

export function RestaurantFilters({
  visitCount,
  rating,
  preference,
  queueDuration,
  companion,
  tag,
  city,
  companionOptions,
  tagOptions,
  cityOptions,
  showVisitCount,
  onVisitCountChange,
  onRatingChange,
  onPreferenceChange,
  onQueueDurationChange,
  onCompanionChange,
  onTagChange,
  onCityChange,
  onReset,
}: RestaurantFiltersProps) {
  return (
    <section className="filters-panel">
      <header><strong>筛选餐厅</strong><button onClick={onReset} type="button">重置</button></header>
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
        <span>我的喜好</span>
        <div>
          <button className={preference === 'all' ? 'is-active' : ''} onClick={() => onPreferenceChange('all')} type="button">全部</button>
          {(Object.entries(PREFERENCE_META) as [PreferenceLevel, (typeof PREFERENCE_META)[PreferenceLevel]][]).map(([value, item]) => (
            <button className={preference === value ? 'is-active' : ''} key={value} onClick={() => onPreferenceChange(value)} type="button">
              <i className="filter-color-dot" style={{ background: item.color }} />{item.label}
            </button>
          ))}
        </div>
      </div>
      <div className="filter-group">
        <span>我的评分</span>
        <div>
          {([
            ['all', '全部'],
            ['9', '≥ 9'],
            ['8', '≥ 8'],
            ['7', '≥ 7'],
            ['unrated', '未评分'],
          ] as [RatingFilter, string][]).map(([value, label]) => (
            <button className={rating === value ? 'is-active' : ''} key={value} onClick={() => onRatingChange(value)} type="button">{label}</button>
          ))}
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
      </div>
    </section>
  )
}

function FilterSelect({
  label,
  value,
  allLabel,
  options,
  onChange,
}: {
  label: string
  value: string
  allLabel: string
  options: string[]
  onChange: (value: string) => void
}) {
  return (
    <label>
      <span>{label}</span>
      <select aria-label={`按${label}筛选`} onChange={(event) => onChange(event.target.value)} value={value}>
        <option value="all">{allLabel}</option>
        {options.map((item) => <option key={item} value={item}>{item}</option>)}
      </select>
    </label>
  )
}
