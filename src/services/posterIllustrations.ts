/** Local editorial artwork, never system glyphs or user/merchant photographs. */
export const POSTER_ILLUSTRATIONS = ['pizza', 'sushi', 'bowl', 'noodles', 'hotpot', 'cake', 'coffee', 'burger', 'leaf', 'salt', 'tomato', 'chili', 'lemon'] as const
export type PosterIllustrationID = typeof POSTER_ILLUSTRATIONS[number]
export function posterIllustration(label: string): PosterIllustrationID {
  if (/咸|盐/.test(label)) return 'salt'
  if (/酸|柠檬/.test(label)) return 'lemon'
  if (/辣/.test(label)) return 'chili'
  if (/鲜/.test(label)) return 'tomato'
  if (/清淡|素|轻食|其他/.test(label)) return 'leaf'
  if (/甜|蛋糕|烘焙/.test(label)) return 'cake'
  if (/咖啡|茶|饮/.test(label)) return 'coffee'
  if (/日|寿司/.test(label)) return 'sushi'
  if (/韩|火锅|烧烤|烤肉/.test(label)) return 'hotpot'
  if (/面|粉/.test(label)) return 'noodles'
  if (/快餐|汉堡|简餐/.test(label)) return 'burger'
  if (/意|西|披萨/.test(label)) return 'pizza'
  return 'bowl'
}
export function posterHeroPath(label: string) {
  const id = posterIllustration(label)
  const family = ({ pizza: 'western', burger: 'western', sushi: 'japanese', hotpot: 'hotpot-grill', coffee: 'cafe', cake: 'cafe', bowl: 'chinese', noodles: 'chinese' } as Partial<Record<PosterIllustrationID, string>>)[id] ?? 'mixed'
  return `/food-heroes/${family}.png`
}
