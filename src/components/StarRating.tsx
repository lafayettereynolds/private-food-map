import { Star } from 'lucide-react'
import { RATING_META, starToTenScore, type StarRating as StarRatingValue } from '../types/domain'

interface StarRatingProps {
  value: StarRatingValue
  onChange: (value: StarRatingValue) => void
}

export function StarRating({ value, onChange }: StarRatingProps) {
  return (
    <div className="star-rating" aria-label={`个人评价 ${value} 星`}>
      <div>
        {([1, 2, 3, 4, 5] as StarRatingValue[]).map((star) => (
          <button
            aria-label={`${star} 星`}
            className={star <= value ? 'is-active' : ''}
            key={star}
            onClick={() => onChange(star)}
            type="button"
          >
            <Star fill={star <= value ? 'currentColor' : 'none'} size={25} />
          </button>
        ))}
      </div>
      <span style={{ color: RATING_META[value].color }}>
        {value} 星 · {RATING_META[value].label} · {starToTenScore(value)?.toFixed(1)} 分
      </span>
    </div>
  )
}
