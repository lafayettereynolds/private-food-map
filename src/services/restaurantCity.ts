/** Recover only an explicit administrative city in an address, never GPS/user city. */
export function restaurantCity(city: string | null | undefined, address: string | null | undefined): string {
  if (city?.trim()) return city.trim()
  const prefix = (address ?? '').trim().replace(/^中国\s*/, '')
  return prefix.match(/^(?:[\p{Script=Han}]{2,10}(?:省|自治区))?([^省市区县\d\s]{2,8}市)/u)?.[1] ?? ''
}

/** Comparison key only: preserve genuine city-name characters such as 杭州/温州.
 * A trailing 市 is an optional Chinese city suffix; 州、区 and 地 are not
 * interchangeable single-character suffixes. Overseas names keep their words.
 */
export function restaurantCityComparisonKey(value: string): string {
  return restaurantCityFilterLabel(value).toLocaleLowerCase('zh-CN')
}

/** Filter presentation only. Never write these labels back to Restaurant.city. */
export function restaurantCityFilterOptions(values: readonly string[]): string[] {
  const byIdentity = new Map<string, string>()
  for (const value of values) {
    const label = restaurantCityFilterLabel(value)
    const key = restaurantCityComparisonKey(label)
    if (key && (!byIdentity.has(key) || label < byIdentity.get(key)!)) byIdentity.set(key, label)
  }
  return [...byIdentity.values()].sort((left, right) => left.localeCompare(right, 'zh-CN'))
}

function restaurantCityFilterLabel(value: string): string {
  return value.normalize('NFKC').trim().replace(/\s+/gu, ' ')
    .replace(/^([\p{Script=Han}]{2,})市$/u, '$1')
}
