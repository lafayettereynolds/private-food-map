import type { CSSProperties } from 'react'
import {
  foodCategoryVisualPalette,
  resolveFoodCategoryVisualID,
  resolveRestaurantFoodEmoji,
  type FoodCategoryVisualID,
} from './FoodCategoryVisualContract'

export function RestaurantFoodEmoji({
  name,
  tags = [],
  categoryVisualID,
  preferredEmoji,
  label = `${name} 食物表情`,
  className = '',
}: {
  name: string
  tags?: readonly string[]
  categoryVisualID?: FoodCategoryVisualID
  preferredEmoji?: string | null
  label?: string
  className?: string
}) {
  const evidence = { name, tags }
  const category = categoryVisualID ?? resolveFoodCategoryVisualID(evidence)
  const emoji = resolveRestaurantFoodEmoji(evidence, preferredEmoji, category)
  const color = foodCategoryVisualPalette[category]
  return <span
    aria-label={label}
    className={`tm-restaurant-food-emoji ${className}`.trim()}
    role="img"
    style={{ '--food-bg': color.background } as CSSProperties}
  ><span aria-hidden="true" className="tm-restaurant-food-emoji__glyph">{emoji}</span></span>
}
