const RESTAURANT_BRAND_ALIASES: Record<string, string> = {
  kfc: '肯德基',
  kentucky: '肯德基',
  mcdonalds: '麦当劳',
  "mcdonald's": '麦当劳',
  starbucks: '星巴克',
  haidilao: '海底捞',
}

/** Platform-neutral keyword normalization shared by Web and future native clients. */
export function normalizeRestaurantKeyword(keyword: string) {
  const normalized = keyword.trim()
  if (!normalized) return ''
  return RESTAURANT_BRAND_ALIASES[normalized.toLocaleLowerCase('en-US')] ?? normalized
}
