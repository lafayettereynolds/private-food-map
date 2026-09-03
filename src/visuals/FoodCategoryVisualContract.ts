/** Stable cross-platform IDs. Keep in sync with FoodCategoryVisualID.swift. */
export const FOOD_CATEGORY_VISUAL_IDS = [
  'chinese', 'japaneseKorean', 'western', 'hotpotBBQ', 'noodles',
  'cafeBakery', 'drinksDessert', 'seafood', 'fastFood',
  'vegetarianLight', 'other',
] as const

export type FoodCategoryVisualID = typeof FOOD_CATEGORY_VISUAL_IDS[number]

export interface FoodCategoryVisualEvidence {
  name?: string | null
  tags?: readonly string[] | null
  providerCategory?: string | null
}

const MATCHERS: ReadonlyArray<readonly [FoodCategoryVisualID, readonly string[]]> = [
  ['hotpotBBQ', ['火锅', '锅物', '涮', '烧肉', '烤肉', '烧烤', '串烧', '烤串', 'bbq', 'barbecue', 'hotpot']],
  ['noodles', ['面馆', '面食', '拉面', '拌面', '米线', '米粉', '河粉', '粉店', '饺子', '馄饨', 'noodle', 'ramen']],
  ['cafeBakery', ['咖啡', 'coffee', 'cafe', '烘焙', '面包', 'bakery', 'brunch', '早午餐']],
  ['drinksDessert', ['甜品', '甜点', '蛋糕', '冰淇淋', '冰激凌', '奶茶', '茶饮', '饮品', '糖水', 'dessert', 'boba', 'tea shop']],
  ['seafood', ['海鲜', '鱼生', '生蚝', '龙虾', '螃蟹', '水产', 'seafood', 'oyster']],
  ['japaneseKorean', ['日料', '日本料理', '寿司', '刺身', '居酒屋', '韩餐', '韩国料理', '韩式', '石锅', 'sushi', 'japanese', 'korean']],
  ['western', ['西餐', '意大利', '法餐', '牛排', '披萨', 'pizza', 'pasta', 'steak', 'bistro', 'western', 'italian', 'french']],
  ['fastFood', ['快餐', '汉堡', '炸鸡', '小吃', '简餐', '便当', 'burger', 'fried chicken', 'fast food']],
  ['vegetarianLight', ['素食', '轻食', '沙拉', '健康餐', '低卡', 'vegetarian', 'vegan', 'salad', 'healthy']],
  ['chinese', ['中餐', '中国菜', '杭帮菜', '江浙菜', '本帮菜', '粤菜', '川菜', '湘菜', '鲁菜', '徽菜', '闽菜', '京菜', '东北菜', '云南菜', '贵州菜', '新疆菜', '火锅店', '餐馆', 'chinese']],
]

export function resolveFoodCategoryVisualID(evidence: FoodCategoryVisualEvidence): FoodCategoryVisualID {
  const haystack = [evidence.name, ...(evidence.tags ?? []), evidence.providerCategory]
    .filter((value): value is string => typeof value === 'string' && value.trim().length > 0)
    .join('|')
    .normalize('NFKC')
    .toLocaleLowerCase('zh-CN')
  return MATCHERS.find(([, needles]) => needles.some((needle) => haystack.includes(needle)))?.[0] ?? 'other'
}

export const foodCategoryVisualPalette: Record<FoodCategoryVisualID, { background: string; accent: string; ink: string }> = {
  chinese: { background: '#FFF0E8', accent: '#E85C4A', ink: '#8D2F2A' },
  japaneseKorean: { background: '#FDECEF', accent: '#E34D6D', ink: '#842641' },
  western: { background: '#F3EDFF', accent: '#7A5BD6', ink: '#49328E' },
  hotpotBBQ: { background: '#FFF0DC', accent: '#F07B32', ink: '#984619' },
  noodles: { background: '#FFF4C9', accent: '#E5A62B', ink: '#845B10' },
  cafeBakery: { background: '#F4E8DD', accent: '#A96F49', ink: '#603C28' },
  drinksDessert: { background: '#FCE9F5', accent: '#D85DA5', ink: '#853263' },
  seafood: { background: '#E5F5FA', accent: '#329BC0', ink: '#16617D' },
  fastFood: { background: '#FFF0D9', accent: '#ED8F2D', ink: '#944B11' },
  vegetarianLight: { background: '#E8F5E4', accent: '#61A64E', ink: '#356B2A' },
  other: { background: '#E9F1F4', accent: '#588397', ink: '#315565' },
}

/** DOM-marker renderer for map SDKs that require an HTML string. */
export function foodCategoryVisualMarkup(id: FoodCategoryVisualID) {
  const color = foodCategoryVisualPalette[id]
  const glyph = id === 'seafood'
    ? '<path d="M21 49c12-18 34-21 49-8l8-9v26l-8-8C55 65 33 64 21 49Z"/><circle cx="38" cy="45" r="2.5"/><path d="M28 56c8 7 20 9 31 4"/>'
    : id === 'vegetarianLight'
      ? '<path d="M23 68c2-26 20-41 51-42-2 30-18 47-45 47"/><path d="M29 69c12-12 24-22 38-32M47 54l-2-15M48 54l16 1"/>'
      : id === 'drinksDessert'
        ? '<path d="M31 34h34l-5 42H36z"/><path d="M35 46h26M52 34l9-14M40 61c5-7 11 7 18-2"/>'
        : id === 'cafeBakery'
          ? '<path d="M24 34h42v24c0 11-8 18-21 18S24 69 24 58Z"/><path d="M66 41h5c9 0 9 15 0 15h-5M34 27c5-7 10 4 15-3M28 62h44"/>'
          : id === 'hotpotBBQ'
            ? '<path d="M20 47h56c0 18-10 28-28 28S20 65 20 47Z"/><path d="M28 40h40M36 30c-5 5 4 7-1 12M49 25c-6 7 5 9-1 16M62 30c-5 5 4 7-1 12"/>'
            : id === 'noodles'
              ? '<path d="M19 52h58c-2 17-13 24-29 24S21 69 19 52Z"/><path d="M29 43c7-12 8 5 18-8 8-10 11 9 21-3M31 27l9 27M64 25 53 54"/>'
              : id === 'western'
                ? '<path d="M24 67h48M29 60h38l-8-28H37z"/><path d="M34 44h28M44 32l4 28M59 30l-7 30"/>'
                : id === 'fastFood'
                  ? '<path d="M22 49h52M27 42c3-12 12-18 21-18s18 6 21 18zM25 57h46l-5 17H30z"/><path d="M31 53h34"/>'
                  : id === 'japaneseKorean'
                    ? '<path d="M25 58c0-20 10-31 23-31s23 11 23 31"/><path d="M20 58h56c-2 12-12 18-28 18S22 70 20 58Z"/><circle cx="40" cy="45" r="4"/><circle cx="55" cy="39" r="5"/>'
                    : id === 'chinese'
                      ? '<path d="M22 38h52l-5 29H27z"/><path d="M31 32c7-8 27-8 34 0M36 48h24M48 25v35"/>'
                      : '<circle cx="48" cy="48" r="27"/><path d="M36 38h24M32 49h32M37 60h22"/>'
  return `<svg aria-hidden="true" viewBox="0 0 96 96" style="background:${color.background};border-radius:22px"><g fill="${color.accent}29" stroke="${color.ink}" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round">${glyph}</g></svg>`
}
