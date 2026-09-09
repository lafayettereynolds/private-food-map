/** Provider identifiers are transport metadata, never user-facing cuisine names. */
export function restaurantCategoryLabels(tags: readonly string[]): string[] {
  const labels: Record<string, string> = { MKPOICategoryRestaurant: '餐厅', MKPOICategoryCafe: '咖啡馆', MKPOICategoryBakery: '烘焙', MKPOICategoryBrewery: '精酿啤酒', MKPOICategoryWinery: '酒庄', MKPOICategoryFoodMarket: '食品市场' }
  return [...new Set(tags.map(tag => tag.trim()).map(tag => labels[tag] ?? (tag.startsWith('MKPOICategory') ? '' : tag)).filter(Boolean))]
}
