import catalog from '../../public/food-library/catalog.json'
import type { FoodCategoryVisualID } from './FoodCategoryVisualContract'
import './foodLibraryArtwork.css'

export function resolveFoodLibraryArtwork({ name = '', tags = [], categoryVisualID = 'other' }: {
  name?: string; tags?: readonly string[]; categoryVisualID?: FoodCategoryVisualID
}) {
  // Restaurant-name evidence leads broad cuisine tags (coffee + brunch => coffee).
  const normalized = (text: string) => text.normalize('NFKC').toLocaleLowerCase('zh-CN')
  const match = (text: string) => catalog.entries.find(entry => entry.keywords.some(keyword => normalized(text).includes(keyword)))
  return match(name) ?? match(tags.join('|'))
    ?? catalog.entries.find(entry => entry.id === catalog.categoryDefaults[categoryVisualID])!
}

/** Supplied original sheets, viewport-cropped at render time; never a user photo. */
export function FoodLibraryArtwork({ name, tags, categoryVisualID, className = '' }: {
  name: string; tags?: readonly string[]; categoryVisualID?: FoodCategoryVisualID; className?: string
}) {
  const entry = resolveFoodLibraryArtwork({ name, tags, categoryVisualID })
  const crop = (catalog.crops as Record<string, number[]>)[entry.id]
  const width = crop?.[2] ?? catalog.sheetWidth / catalog.columns
  const left = crop?.[0] ?? entry.column * width
  const top = crop?.[1] ?? catalog.rowEdges[entry.row]
  const height = crop?.[3] ?? catalog.rowEdges[entry.row + 1] - top
  return <svg className={`tm-food-library-artwork ${className}`.trim()}
    data-food-library-artwork={entry.id} data-image-provenance="illustration"
    role="img" aria-label={`${name} · ${entry.label}素材插画（非餐厅实拍）`}
    viewBox={`0 0 ${width} ${height}`}
    preserveAspectRatio="xMidYMid meet">
    <svg width={width} height={height} overflow="hidden">
      <image href={`/food-library/${entry.sheet}.png`} x={-left} y={-top}
        width={catalog.sheetWidth} height={catalog.sheetHeight} />
    </svg>
  </svg>
}
