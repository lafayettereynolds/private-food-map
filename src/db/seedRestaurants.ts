import { db } from './appDb'
import { calculatePricePerPerson, type QueueDuration, type Restaurant, type StarRating, type Visit } from '../types/domain'

const names = [
  '桂满陇·江南小馆（来福士店）', '山葵家精致料理（来福士店）', '浅草君日式烧肉（来福士店）', '椒响川菜（来福士店）', '南洋里新加坡料理（来福士店）',
  '潮上潮汕牛肉锅（来福士店）', '月影铁板烧（来福士店）', '云炉云南菜（来福士店）', '金栗韩式烤肉（来福士店）', '鹿港小镇（来福士店）',
  '拾味融合菜（来福士店）', '海风里海鲜餐厅（来福士店）', '小吊梨汤（来福士店）', '樱田寿司（来福士店）', '炙焰牛排馆（来福士店）',
  '泰香米泰国菜（来福士店）', '江户前寿司（来福士店）', '福气粤菜馆（来福士店）', '麦香意面坊（来福士店）', '一炉一会炭火烧鸟（来福士店）',
  '新白鹿餐厅（湖滨银泰店）', '外婆家（湖滨银泰店）', '湖滨里杭帮菜（湖滨银泰店）', '赤坂亭烧肉（湖滨银泰店）', '捞王锅物料理（湖滨银泰店）',
  '西塔老太太泥炉烤肉（湖滨银泰店）', '九本居酒屋（湖滨银泰店）', '山缓缓火锅（湖滨银泰店）', '阿嬷手作（湖滨银泰店）', '兰巴赫西餐啤酒坊（湖滨银泰店）',
  '宴西湖（湖滨银泰店）', '江边城外烤全鱼（湖滨银泰店）', '肉本家（湖滨银泰店）', '青花椒砂锅鱼（湖滨银泰店）', '稻香酒家（湖滨银泰店）',
  '寿喜烧研究所（湖滨银泰店）', '马路边边串串香（湖滨银泰店）', '王品牛排（湖滨银泰店）', '和府捞面（湖滨银泰店）', '乐忻皇朝（湖滨银泰店）',
  '武林茶餐厅', '西溪别院', '运河畔私房菜', '滨江小馆', '钱江新城炭火料理',
  '城西面馆', '满觉陇山房', '南山路西餐厅', '东站小厨', '龙井草堂',
  '拱宸桥鱼馆', '黄龙海鲜坊', '萧山本味馆', '奥体精酿餐厅', '九堡烧烤研究所',
  '良渚食集', '湘湖人家', '文三路小酒馆', '大兜路素食馆', '复兴路砂锅店',
]

const otherCenters = [
  [120.1692, 30.2746], [120.0648, 30.2722], [120.1434, 30.3192], [120.1908, 30.2088], [120.2129, 30.2479],
  [120.1201, 30.2912], [120.1356, 30.2285], [120.1571, 30.2368], [120.2134, 30.2932], [120.1173, 30.2247],
  [120.1412, 30.3311], [120.1455, 30.2877], [120.2702, 30.1886], [120.2418, 30.2324], [120.2764, 30.3142],
  [120.0131, 30.3794], [120.2452, 30.1477], [120.1238, 30.2819], [120.1586, 30.3096], [120.1748, 30.2149],
] as const

const areaNames = ['武林广场', '西溪', '大运河', '滨江', '钱江新城', '城西', '满觉陇', '南山路', '火车东站', '龙井', '拱宸桥', '黄龙', '萧山', '奥体', '九堡', '良渚', '湘湖', '文三路', '大兜路', '复兴路']
const cuisines = ['杭帮菜', '日料', '火锅', '烧烤', '粤菜', '西餐', '川菜', '融合菜']
const emojis = ['🍲', '🍣', '🥩', '🍜', '🥘', '🍕', '🍤', '🥟']
const queueDurations: QueueDuration[] = ['none', 'under15', 'under30', 'under60', 'under90', 'under120', 'over120']

let seedPromise: Promise<number> | null = null

export function seedSixtyVisitedRestaurants() {
  seedPromise ??= seedRestaurants()
  return seedPromise
}

async function seedRestaurants() {
  const ids = names.map((_, index) => `sample-restaurant-${String(index + 1).padStart(2, '0')}`)
  const existing = await db.restaurants.bulkGet(ids)
  const missingIndexes = existing.flatMap((restaurant, index) => restaurant ? [] : [index])
  if (!missingIndexes.length) return 0

  const restaurants: Restaurant[] = []
  const visits: Visit[] = []
  const now = new Date().toISOString()

  missingIndexes.forEach((index) => {
    const random = seededRandom(index + 20260820)
    const area = index < 20 ? '来福士中心' : index < 40 ? '湖滨银泰' : areaNames[index - 40]
    const center = index < 20
      ? [120.2196, 30.2465] as const
      : index < 40
        ? [120.1631, 30.2575] as const
        : otherCenters[index - 40]
    const radius = index < 40 ? 0.00125 : 0.00045
    const angle = random() * Math.PI * 2
    const distance = Math.sqrt(random()) * radius
    const longitude = center[0] + Math.cos(angle) * distance
    const latitude = center[1] + Math.sin(angle) * distance
    const cuisineIndex = Math.floor(random() * cuisines.length)
    const visitCount = 1 + Math.floor(random() * 4)
    const restaurantId = ids[index]
    const restaurantVisits: Visit[] = []

    for (let visitIndex = 0; visitIndex < visitCount; visitIndex += 1) {
      const partySize = 1 + Math.floor(random() * 6)
      const totalPrice = 60 + Math.round(random() * 740)
      const rating = (1 + Math.floor(random() * 5)) as StarRating
      const visitedAt = new Date(Date.now() - Math.floor(random() * 630) * 86400000 - visitIndex * 86400000).toISOString()
      restaurantVisits.push({
        id: `${restaurantId}-visit-${visitIndex + 1}`,
        restaurantId,
        visitedAt,
        rating,
        totalPrice,
        pricePerPerson: calculatePricePerPerson(totalPrice, partySize),
        partySize,
        queueDuration: queueDurations[Math.floor(random() * queueDurations.length)],
        companions: partySize > 1 ? randomCompanions(partySize - 1, random) : [],
        dishes: [],
        note: random() > 0.55 ? ['味道比预期好，会再来。', '环境舒服，适合朋友聚餐。', '出餐很快，招牌菜值得点。', '整体不错，下次想试试别的菜。'][Math.floor(random() * 4)] : '',
        photos: [],
        photoIds: [],
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      })
    }
    visits.push(...restaurantVisits)
    const averageRating = restaurantVisits.reduce((sum, visit) => sum + (visit.rating ?? 0), 0) / restaurantVisits.length
    const averagePrice = Math.round(restaurantVisits.reduce((sum, visit) => sum + (visit.pricePerPerson ?? 0), 0) / restaurantVisits.length)
    restaurants.push({
      id: restaurantId,
      amapPoiId: `sample-amap-poi-${String(index + 1).padStart(2, '0')}`,
      name: names[index],
      address: `${area}附近 ${20 + index} 号`,
      city: '杭州市',
      latitude,
      longitude,
      status: 'visited',
      preferenceLevel: averageRating >= 4.5 ? 'favorite' : averageRating >= 3.5 ? 'like' : averageRating >= 2.5 ? 'normal' : 'avoid',
      overallRating: null,
      foodRating: null,
      environmentRating: null,
      serviceRating: null,
      valueRating: null,
      tags: [cuisines[cuisineIndex], area],
      longTermNote: '',
      pricePerPerson: averagePrice,
      markerType: 'emoji',
      markerImageData: null,
      markerPhotoId: null,
      merchantImageUrl: null,
      markerEmoji: emojis[cuisineIndex],
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    })
  })

  await db.transaction('rw', db.restaurants, db.visits, async () => {
    await db.restaurants.bulkPut(restaurants)
    await db.visits.bulkPut(visits)
  })
  return restaurants.length
}

function seededRandom(seed: number) {
  let state = seed >>> 0
  return () => {
    state += 0x6d2b79f5
    let value = state
    value = Math.imul(value ^ (value >>> 15), value | 1)
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61)
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296
  }
}

function randomCompanions(count: number, random: () => number) {
  const pool = ['小王', '妈妈', '同事', '朋友', '家人']
  return [...new Set(Array.from({ length: Math.min(count, 3) }, () => pool[Math.floor(random() * pool.length)]))]
}
