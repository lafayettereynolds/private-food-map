import type { CSSProperties } from 'react'
import { foodCategoryVisualPalette, type FoodCategoryVisualID } from './FoodCategoryVisualContract'

export function FoodCategoryVisual({ id, label, className = '' }: {
  id: FoodCategoryVisualID
  label: string
  className?: string
}) {
  const color = foodCategoryVisualPalette[id]
  return <div
    aria-label={label}
    className={`tm-food-category-visual is-${id} ${className}`}
    role="img"
    style={{ '--food-bg': color.background, '--food-accent': color.accent, '--food-ink': color.ink } as CSSProperties}
  >
    <svg aria-hidden="true" viewBox="0 0 96 96"><CategoryGlyph id={id} /></svg>
  </div>
}

function CategoryGlyph({ id }: { id: FoodCategoryVisualID }) {
  switch (id) {
  case 'chinese': return <><path d="M22 38h52l-5 29H27z" /><path d="M31 32c7-8 27-8 34 0M36 48h24M48 25v35" /></>
  case 'japaneseKorean': return <><path d="M25 58c0-20 10-31 23-31s23 11 23 31" /><path d="M20 58h56c-2 12-12 18-28 18S22 70 20 58Z" /><circle cx="40" cy="45" r="4" /><circle cx="55" cy="39" r="5" /></>
  case 'western': return <><path d="M24 67h48M29 60h38l-8-28H37z" /><path d="M34 44h28M44 32l4 28M59 30l-7 30" /></>
  case 'hotpotBBQ': return <><path d="M20 47h56c0 18-10 28-28 28S20 65 20 47Z" /><path d="M28 40h40M36 30c-5 5 4 7-1 12M49 25c-6 7 5 9-1 16M62 30c-5 5 4 7-1 12" /></>
  case 'noodles': return <><path d="M19 52h58c-2 17-13 24-29 24S21 69 19 52Z" /><path d="M29 43c7-12 8 5 18-8 8-10 11 9 21-3M31 27l9 27M64 25 53 54" /></>
  case 'cafeBakery': return <><path d="M24 34h42v24c0 11-8 18-21 18S24 69 24 58Z" /><path d="M66 41h5c9 0 9 15 0 15h-5M34 27c5-7 10 4 15-3M28 62h44" /></>
  case 'drinksDessert': return <><path d="M31 34h34l-5 42H36z" /><path d="M35 46h26M52 34l9-14M40 61c5-7 11 7 18-2" /></>
  case 'seafood': return <><path d="M21 49c12-18 34-21 49-8l8-9v26l-8-8C55 65 33 64 21 49Z" /><circle cx="38" cy="45" r="2.5" /><path d="M28 56c8 7 20 9 31 4" /></>
  case 'fastFood': return <><path d="M22 49h52M27 42c3-12 12-18 21-18s18 6 21 18zM25 57h46l-5 17H30z" /><path d="M31 53h34" /></>
  case 'vegetarianLight': return <><path d="M23 68c2-26 20-41 51-42-2 30-18 47-45 47" /><path d="M29 69c12-12 24-22 38-32M47 54l-2-15M48 54l16 1" /></>
  case 'other': return <><circle cx="48" cy="48" r="27" /><path d="M36 38h24M32 49h32M37 60h22" /></>
  }
}
