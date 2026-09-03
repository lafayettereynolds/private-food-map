import { Star } from 'lucide-react'
import { ratingColor, ratingLabel, starToTenScore, type StarRating as StarRatingValue } from '../types/domain'
import { reduceEditableStarRating } from '../utils/starRatingInteraction'

interface StarRatingProps {
  value: StarRatingValue | null
  onChange: (value: StarRatingValue | null) => void
  ariaLabel?: string
  compact?: boolean
  showSummary?: boolean
}

interface StarRatingFieldProps extends StarRatingProps {
  label?: string
  optional?: boolean
}

export function StarRating({
  value,
  onChange,
  ariaLabel = '个人评价',
  compact = false,
  showSummary = true,
}: StarRatingProps) {
  const accessibleValue = value == null
    ? `${ariaLabel}，未评分，共 5 星`
    : `${ariaLabel}，${value} 星，共 5 星`

  function setRating(nextValue: StarRatingValue) {
    onChange(reduceEditableStarRating(value, { type: 'set', value: nextValue }))
  }

  return (
    <div className={`star-rating${compact ? ' star-rating--compact' : ''}`}>
      <div aria-label={accessibleValue} className="star-rating__stars" role="group">
        <div className="star-rating__targets">
          {([0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5] as const).map((target) => (
            <button
              aria-label={`设置${ariaLabel}为 ${target} 星`}
              aria-pressed={value === target}
              data-rating-target={target}
              key={target}
              onClick={() => setRating(target)}
              type="button"
            >
              <span className="star-rating__target-label">设置{ariaLabel}为 {target} 星</span>
            </button>
          ))}
        </div>
        {([1, 2, 3, 4, 5] as const).map((star) => {
          const fillPercent = value == null ? 0 : value >= star ? 100 : value === star - 0.5 ? 50 : 0
          return (
            <span
              aria-hidden="true"
              className="star-rating__star"
              data-star={star}
              key={star}
              title={`左半 ${star - 0.5} 星，右半 ${star} 星`}
            >
              <span className="star-rating__visual">
                <Star className="star-rating__base" size={27} />
                <span className="star-rating__fill" style={{ width: `${fillPercent}%` }}><Star fill="currentColor" size={27} /></span>
              </span>
            </span>
          )
        })}
      </div>
      {showSummary ? value == null ? <span className="star-rating__summary star-rating__empty">未评分 · 可直接保存</span> : (
        <span className="star-rating__summary" style={{ color: ratingColor(value) }}><output aria-live="polite">{value} 星 · {ratingLabel(value)} · {starToTenScore(value)?.toFixed(1)} 分</output> <button aria-label="清除评分" className="star-rating__clear" onClick={(event) => { event.preventDefault(); event.stopPropagation(); onChange(reduceEditableStarRating(value, { type: 'clear' })) }} type="button">清除</button></span>
      ) : null}
    </div>
  )
}

/** Semantic field wrapper for the editable rating widget. */
export function StarRatingField({ label = '个人评价', optional = true, ...ratingProps }: StarRatingFieldProps) {
  return (
    <fieldset className="field rating-field">
      <legend>{label}{optional ? <small>可选</small> : null}</legend>
      <StarRating {...ratingProps} ariaLabel={ratingProps.ariaLabel ?? label} />
    </fieldset>
  )
}
