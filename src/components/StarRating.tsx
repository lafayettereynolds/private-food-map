import { Star } from 'lucide-react'
import { ratingColor, ratingLabel, starToTenScore, type StarRating as StarRatingValue } from '../types/domain'

interface StarRatingProps {
  value: StarRatingValue | null
  onChange: (value: StarRatingValue | null) => void
}

export function StarRating({ value, onChange }: StarRatingProps) {
  return (
    <div className="star-rating" aria-label={value ? `个人评价 ${value} 星` : '个人评价未评分'}>
      <div className="star-rating__stars">
        {([1, 2, 3, 4, 5] as const).map((star) => {
          const fillPercent = value == null ? 0 : value >= star ? 100 : value === star - 0.5 ? 50 : 0
          return (
            <span className="star-rating__star" key={star}>
              <Star className="star-rating__base" size={27} />
              <span className="star-rating__fill" style={{ width: `${fillPercent}%` }}><Star fill="currentColor" size={27} /></span>
              <button aria-label={`${star - 0.5} 星`} className="star-rating__hit star-rating__hit--left" onClick={() => onChange((star - 0.5) as StarRatingValue)} type="button" />
              <button aria-label={`${star} 星`} className="star-rating__hit star-rating__hit--right" onClick={() => onChange(star as StarRatingValue)} type="button" />
            </span>
          )
        })}
      </div>
      {value == null ? <span className="star-rating__empty">未评分 · 可直接保存</span> : (
        <span style={{ color: ratingColor(value) }}>{value} 星 · {ratingLabel(value)} · {starToTenScore(value)?.toFixed(1)} 分 <button className="star-rating__clear" onClick={() => onChange(null)} type="button">清除</button></span>
      )}
    </div>
  )
}
