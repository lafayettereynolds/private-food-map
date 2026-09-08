import type { PoiSearchResult } from '../types/domain'
import { normalizeRestaurantKeyword } from './restaurantSearch'

type RestaurantSearchable = Pick<PoiSearchResult, 'name' | 'address' | 'city' | 'district'>

export function rankRestaurantSearchMatches<T extends RestaurantSearchable>(
  values: readonly T[],
  query: string,
): T[] {
  const normalizedQuery = normalizeSearchText(query)
  const compactQuery = compactSearchText(normalizedQuery)
  const queryTerms = searchTerms(normalizedQuery)
  if (!compactQuery) return []

  return values.map((value, index) => ({ value, index, score: restaurantSearchScore(value, compactQuery, queryTerms) }))
    .filter((entry): entry is typeof entry & { score: number } => entry.score != null)
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .map(({ value }) => value)
}

function restaurantSearchScore(value: RestaurantSearchable, compactQuery: string, queryTerms: string[]) {
  const name = compactSearchText(normalizeSearchText(value.name))
  const address = compactSearchText(normalizeSearchText(value.address))
  const searchable = compactSearchText(normalizeSearchText([value.name, value.address, value.city, value.district].join(' ')))
  if (name === compactQuery) return 1_000
  if (name.startsWith(compactQuery)) return 900
  if (name.includes(compactQuery)) return 850
  const alias = compactSearchText(normalizeSearchText(normalizeRestaurantKeyword(compactQuery)))
  if (alias !== compactQuery && name.includes(alias)) return 825
  if (matchesDiningAbbreviation(name, compactQuery)) return 825
  if (address.includes(compactQuery)) return 750
  if (queryTerms.length && queryTerms.every((term) => searchable.includes(compactSearchText(term)))) return 600
  return null
}

// Keep the brand/place prefix and the food noun intact; allow only a short
// qualifier between them (兰州 + 牛肉 + 拉面), not arbitrary fuzzy characters.
function matchesDiningAbbreviation(name: string, query: string) {
  return ['拉面', '火锅', '烧烤', '咖啡', '寿司', '面馆', '奶茶'].some((suffix) => {
    if (!query.endsWith(suffix)) return false
    const prefix = query.slice(0, -suffix.length)
    if (prefix.length < 2) return false
    const start = name.indexOf(prefix)
    if (start < 0) return false
    const gap = name.slice(start + prefix.length).indexOf(suffix)
    return gap >= 0 && gap <= 6
  })
}

function normalizeSearchText(value: string) {
  return value.normalize('NFKC').trim().toLocaleLowerCase('zh-CN')
}

function searchTerms(value: string) {
  return value.match(/[\p{L}\p{N}]+/gu) ?? []
}

function compactSearchText(value: string) {
  return searchTerms(value).join('')
}
