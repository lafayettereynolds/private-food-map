import { db } from './appDb'
import { LOCAL_TEST_ACCOUNT, LOCAL_TEST_VIEWER_ID } from '../config/appEnvironment'
import { calculatePricePerPerson, type DiningCompanion, type QueueDuration, type Restaurant, type RestaurantListCollection, type RestaurantListItem, type StarRating, type Visit } from '../types/domain'

const hangzhouNames = [
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

const crossCitySeeds = [
  { name: '梧桐里本帮菜（静安店）', city: '上海市', area: '静安寺', longitude: 121.4452, latitude: 31.2231 },
  { name: '外滩小馆（黄浦店）', city: '上海市', area: '外滩', longitude: 121.4908, latitude: 31.2383 },
  { name: '胡同里涮肉（东城店）', city: '北京市', area: '东城区', longitude: 116.4188, latitude: 39.9287 },
  { name: '京味小院（朝阳店）', city: '北京市', area: '三里屯', longitude: 116.4551, latitude: 39.9364 },
  { name: '荔湾艇仔粥（西关店）', city: '广州市', area: '荔湾区', longitude: 113.2484, latitude: 23.1189 },
  { name: '珠江夜宴（天河店）', city: '广州市', area: '天河区', longitude: 113.3278, latitude: 23.1292 },
  { name: '南山海鲜档（后海店）', city: '深圳市', area: '南山区', longitude: 113.9424, latitude: 22.5177 },
  { name: '福田潮汕牛肉锅', city: '深圳市', area: '福田区', longitude: 114.0579, latitude: 22.5417 },
  { name: '玉林串串香（武侯店）', city: '成都市', area: '玉林', longitude: 104.0532, latitude: 30.6255 },
  { name: '宽窄巷子川味馆', city: '成都市', area: '青羊区', longitude: 104.0557, latitude: 30.6714 },
  { name: '金陵盐水鸭（夫子庙店）', city: '南京市', area: '夫子庙', longitude: 118.7882, latitude: 32.0205 },
  { name: '玄武湖畔小馆', city: '南京市', area: '玄武区', longitude: 118.8036, latitude: 32.0718 },
  { name: '平江路苏帮菜', city: '苏州市', area: '姑苏区', longitude: 120.6357, latitude: 31.3147 },
  { name: '金鸡湖融合料理', city: '苏州市', area: '工业园区', longitude: 120.7054, latitude: 31.3226 },
  { name: '中环茶餐厅', city: '香港', area: '中环', longitude: 114.1579, latitude: 22.2849 },
  { name: '尖沙咀烧味', city: '香港', area: '尖沙咀', longitude: 114.1722, latitude: 22.2976 },
] as const

const names = [...hangzhouNames, ...crossCitySeeds.map((item) => item.name)]

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
const TEST_SEED_VERSION = 'taste-map-dev-restaurants-2026-08-25-v4-cross-city'
const FREE_TEST_SEED_VERSION = 'taste-map-test-seed-2026-08-26-v6-companion-insights'
export const TASTE_MAP_TEST_SEED = 20260826

let seedPromise: Promise<number> | null = null

export function seedSixtyVisitedRestaurants() {
  seedPromise ??= seedRestaurants()
  return seedPromise
}

async function seedRestaurants() {
  if (LOCAL_TEST_ACCOUNT === 'free') return seedFreeTestAccount()
  const ids = names.map((_, index) => `sample-restaurant-${String(index + 1).padStart(2, '0')}`)
  const existing = await db.restaurants.bulkGet(ids)
  const isCurrentSeed = typeof window !== 'undefined' && window.localStorage.getItem('taste-map-dev-restaurant-seed') === TEST_SEED_VERSION
  if (isCurrentSeed && existing.every(Boolean)) return 0

  const restaurants: Restaurant[] = []
  const visits: Visit[] = []
  const now = new Date().toISOString()

  names.forEach((_, index) => {
    const random = seededRandom(index + 20260820)
    const crossCity = index >= hangzhouNames.length ? crossCitySeeds[index - hangzhouNames.length] : null
    const area = crossCity?.area ?? (index < 20 ? '来福士中心' : index < 40 ? '湖滨银泰' : areaNames[index - 40])
    const center = crossCity
      ? [crossCity.longitude, crossCity.latitude] as const
      : index < 20
      ? [120.2196, 30.2465] as const
      : index < 40
        ? [120.1631, 30.2575] as const
        : otherCenters[index - 40]
    const radius = crossCity ? 0.0022 : index < 40 ? 0.00125 : 0.00045
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
        userId: 'owner',
        restaurantId,
        visitedAt,
        rating,
        visibility: 'private',
        diningMode: random() > 0.18 ? 'dine_in' : 'takeout',
        totalPrice,
        myActualSpend: null,
        paymentMode: null,
        pricePerPerson: calculatePricePerPerson(totalPrice, partySize),
        partySize,
        queueDuration: queueDurations[Math.floor(random() * queueDurations.length)],
        diningOccasions: [(['solo', 'friends', 'family', 'date'] as const)[Math.floor(random() * 4)]],
        diningOccasion: null,
        diningOccasionText: '',
        valueRating: rating,
        environmentRating: (1 + Math.floor(random() * 5)) as StarRating,
        serviceRating: (1 + Math.floor(random() * 5)) as StarRating,
        valueTags: [(['划算', '合理', '偏贵', '超值'] as const)[Math.floor(random() * 4)]],
        environmentTags: [(['安静', '热闹', '舒适', '有氛围'] as const)[Math.floor(random() * 4)]],
        serviceTags: [(['热情', '专业', '高效', '周到'] as const)[Math.floor(random() * 4)]],
        noiseLevel: (['quiet', 'normal', 'loud'] as const)[Math.floor(random() * 3)],
        diningDuration: (['under30', 'under45', 'under60', 'under90'] as const)[Math.floor(random() * 4)],
        portionLevel: (['small', 'normal', 'generous'] as const)[Math.floor(random() * 3)],
        transportConvenience: (['very_convenient', 'convenient', 'normal'] as const)[Math.floor(random() * 3)],
        specialNotes: random() > 0.72 ? '周末高峰建议提前到店。' : '',
        recommendationSourceType: (['friend', 'xiaohongshu', 'dianping', 'self'] as const)[Math.floor(random() * 4)],
        recommendationSourceUserId: null,
        recommendationSourceText: ['朋友推荐', '收藏后到店', '附近发现', '再次到访'][Math.floor(random() * 4)],
        sharedMealId: null,
        companions: partySize > 1 ? randomCompanions(partySize - 1, random) : [],
        companionIds: [],
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
      userId: 'owner',
      amapPoiId: `sample-amap-poi-${String(index + 1).padStart(2, '0')}`,
      name: names[index],
      address: `${area}附近 ${20 + index} 号`,
      city: crossCity?.city ?? '杭州市',
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
      phone: crossCity ? null : `0571-${String(86000000 + index * 137).slice(0, 8)}`,
      openingHours: index % 5 === 0 ? '10:30–23:00' : '11:00–22:00',
      markerType: 'image',
      markerImageData: null,
      markerPhotoId: null,
      merchantImageUrl: foodImageUrl(cuisines[cuisineIndex]),
      markerEmoji: emojis[cuisineIndex],
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      isTestData: true,
    })
  })

  await db.transaction('rw', db.restaurants, db.visits, async () => {
    await db.visits.where('restaurantId').anyOf(ids).delete()
    await db.restaurants.bulkPut(restaurants)
    await db.visits.bulkPut(visits)
  })
  if (typeof window !== 'undefined') window.localStorage.setItem('taste-map-dev-restaurant-seed', TEST_SEED_VERSION)
  return restaurants.length
}

async function seedFreeTestAccount() {
  const storageKey = `taste-map-test-seed:${LOCAL_TEST_VIEWER_ID}`
  const ids = Array.from({ length: 50 }, (_, index) => `free-tester-sample-restaurant-${String(index + 1).padStart(2, '0')}`)
  const isCurrentSeed = typeof window !== 'undefined' && window.localStorage.getItem(storageKey) === FREE_TEST_SEED_VERSION
  const existing = await db.restaurants.bulkGet(ids)
  if (isCurrentSeed && existing.every(Boolean)) return 0

  const tokyoSeeds = [
    { name: '银座鮨青木', city: '东京都', area: '银座', longitude: 139.7647, latitude: 35.6717 },
    { name: '代官山烧鸟研究所', city: '东京都', area: '代官山', longitude: 139.7038, latitude: 35.6481 },
    { name: '表参道咖啡小馆', city: '东京都', area: '表参道', longitude: 139.7122, latitude: 35.6652 },
    { name: '新宿出汁料理', city: '东京都', area: '新宿', longitude: 139.7006, latitude: 35.6903 },
  ] as const
  const freeSeeds = [
    ...hangzhouNames.slice(0, 42).map((name, index) => ({ name, city: '杭州市', area: index < 20 ? '来福士中心' : index < 40 ? '湖滨银泰' : areaNames[index - 40], longitude: NaN, latitude: NaN })),
    ...crossCitySeeds.slice(0, 4),
    ...tokyoSeeds,
  ]
  const visitCounts = [6, 5, 5, 5, 4, 4, 4, 4, 3, 3, ...Array.from({ length: 25 }, () => 1)]
  const restaurants: Restaurant[] = []
  const visits: Visit[] = []
  const now = new Date('2026-08-25T12:00:00.000Z').toISOString()
  const sourceTypes = ['friend', 'xiaohongshu', 'douyin', 'dianping', 'other', 'other', 'self', 'other'] as const
  const sourceLabels = ['朋友小王', '小红书', '抖音', '大众点评', '为你推荐', '同味之选', '路过发现', '同事推荐']
  const companions: DiningCompanion[] = [
    { id: 'free-tester-companion-1', displayName: '小王', linkedUserId: 'discovery-user-01', privateAvatarData: null, relationshipLabel: '朋友' },
    { id: 'free-tester-companion-2', displayName: '妈妈', linkedUserId: 'discovery-user-02', privateAvatarData: null, relationshipLabel: '家人' },
    { id: 'free-tester-companion-3', displayName: '同事阿宁', linkedUserId: null, privateAvatarData: privateCompanionAvatarData('宁', '#506C8C'), relationshipLabel: '同事' },
    { id: 'free-tester-companion-4', displayName: '大学朋友', linkedUserId: null, privateAvatarData: null, relationshipLabel: '同学' },
    { id: 'free-tester-companion-5', displayName: '表姐', linkedUserId: null, privateAvatarData: null, relationshipLabel: '亲友' },
    { id: 'free-tester-companion-6', displayName: '黄渝梭', linkedUserId: null, privateAvatarData: null, relationshipLabel: '朋友' },
    { id: 'free-tester-companion-7', displayName: '朋友', linkedUserId: null, privateAvatarData: null, relationshipLabel: '朋友' },
    { id: 'free-tester-companion-8', displayName: '家人', linkedUserId: null, privateAvatarData: null, relationshipLabel: '家人' },
  ].map((companion) => ({
    ...companion,
    ownerUserId: LOCAL_TEST_VIEWER_ID,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  }))
  const companionById = new Map(companions.map((companion) => [companion.id, companion]))

  freeSeeds.forEach((seed, index) => {
    const random = seededRandom(TASTE_MAP_TEST_SEED + index * 97)
    const cuisineIndex = index % cuisines.length
    let longitude = seed.longitude
    let latitude = seed.latitude
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) {
      const center = index < 20 ? [120.2196, 30.2465] as const : index < 40 ? [120.1631, 30.2575] as const : otherCenters[(index - 40) % otherCenters.length]
      const angle = random() * Math.PI * 2
      const distance = Math.sqrt(random()) * (index < 40 ? 0.00125 : 0.0005)
      longitude = center[0] + Math.cos(angle) * distance
      latitude = center[1] + Math.sin(angle) * distance
    }
    const restaurantId = ids[index]
    const count = visitCounts[index] ?? 0
    const restaurantVisits: Visit[] = []
    for (let visitIndex = 0; visitIndex < count; visitIndex += 1) {
      const companionIds = freeSeedCompanionIds(index, visitIndex)
      const companionNames = companionIds
        .map((companionId) => companionById.get(companionId)?.displayName)
        .filter((displayName): displayName is string => Boolean(displayName))
      const partySize = Math.max(1 + Math.floor(random() * 5), companionNames.length + 1)
      const totalPrice = 58 + Math.round(random() * 680)
      const rating = random() < 0.08 ? null : ((2 + Math.round(random() * 6) / 2) as StarRating)
      const visitedAt = new Date(Date.parse(now) - (index * 11 + visitIndex * 37 + Math.floor(random() * 20)) * 86400000).toISOString()
      const sourceIndex = (index + visitIndex) % sourceTypes.length
      restaurantVisits.push({
        id: `${restaurantId}-visit-${visitIndex + 1}`,
        userId: LOCAL_TEST_VIEWER_ID,
        restaurantId,
        visitedAt,
        rating,
        visibility: visitIndex % 4 === 0 ? 'public' : 'private',
        diningMode: random() > 0.2 ? 'dine_in' : 'takeout',
        totalPrice,
        myActualSpend: Math.round((totalPrice / partySize) * 100) / 100,
        paymentMode: partySize === 1 ? null : (['aa', 'my_treat', 'treated', 'separate'] as const)[Math.floor(random() * 4)],
        pricePerPerson: calculatePricePerPerson(totalPrice, partySize),
        partySize,
        queueDuration: queueDurations[Math.floor(random() * queueDurations.length)],
        diningOccasions: [(['solo', 'friends', 'family', 'date', 'business'] as const)[Math.floor(random() * 5)]],
        diningOccasion: null,
        diningOccasionText: '',
        valueRating: rating,
        environmentRating: rating ? (Math.max(1, Math.min(5, rating + (random() > 0.5 ? 0.5 : -0.5))) as StarRating) : null,
        serviceRating: rating,
        valueTags: [(['划算', '合理', '偏贵', '超值'] as const)[Math.floor(random() * 4)]],
        environmentTags: [(['安静', '热闹', '舒适', '有氛围'] as const)[Math.floor(random() * 4)]],
        serviceTags: [(['热情', '专业', '高效', '周到'] as const)[Math.floor(random() * 4)]],
        noiseLevel: (['quiet', 'normal', 'loud'] as const)[Math.floor(random() * 3)],
        diningDuration: (['under30', 'under45', 'under60', 'under90'] as const)[Math.floor(random() * 4)],
        portionLevel: (['small', 'normal', 'generous'] as const)[Math.floor(random() * 3)],
        transportConvenience: (['very_convenient', 'convenient', 'normal'] as const)[Math.floor(random() * 3)],
        specialNotes: random() > 0.72 ? '周末高峰建议提前到店。' : '',
        recommendationSourceType: sourceTypes[sourceIndex],
        recommendationSourceUserId: sourceTypes[sourceIndex] === 'friend' ? 'discovery-user-01' : null,
        recommendationSourceText: sourceLabels[sourceIndex],
        sharedMealId: null,
        companions: companionNames,
        companionIds,
        dishes: random() > 0.45 ? [{ id: `${restaurantId}-dish-${visitIndex + 1}`, name: ['招牌烤肉', '季节刺身', '特色锅物', '手作甜品'][index % 4], taste: ['鲜香', '清爽', '浓郁', '微甜'][index % 4], rating, price: 28 + index % 8 * 9, imageData: null, photoId: null }] : [],
        note: random() > 0.35 ? ['味道比预期好，会再来。', '环境舒服，适合朋友聚餐。', '招牌菜稳定，服务也很周到。', '这次体验一般，下次会换一道菜。'][Math.floor(random() * 4)] : '',
        photos: [],
        photoIds: [],
        createdAt: visitedAt,
        updatedAt: visitedAt,
        deletedAt: null,
        isTestData: true,
      })
    }
    visits.push(...restaurantVisits)
    const rated = restaurantVisits.filter((visit) => visit.rating !== null)
    const averageRating = rated.length ? rated.reduce((sum, visit) => sum + (visit.rating ?? 0), 0) / rated.length : null
    const averagePrice = restaurantVisits.length ? Math.round(restaurantVisits.reduce((sum, visit) => sum + (visit.pricePerPerson ?? 0), 0) / restaurantVisits.length) : 70 + index * 3
    restaurants.push({
      id: restaurantId,
      userId: LOCAL_TEST_VIEWER_ID,
      amapPoiId: `free-test-poi-${String(index + 1).padStart(2, '0')}`,
      name: seed.name,
      address: `${seed.area}附近 ${20 + index} 号`,
      city: seed.city,
      latitude,
      longitude,
      status: count > 0 ? 'visited' : 'wantToGo',
      preferenceLevel: averageRating === null ? 'normal' : averageRating >= 4.5 ? 'favorite' : averageRating >= 3.5 ? 'like' : averageRating >= 2.5 ? 'normal' : 'avoid',
      overallRating: null,
      foodRating: null,
      environmentRating: null,
      serviceRating: null,
      valueRating: null,
      tags: [cuisines[cuisineIndex]],
      longTermNote: count > 1 ? '多次到访，整体表现稳定。' : '',
      pricePerPerson: averagePrice,
      phone: seed.city === '杭州市' ? `0571-${String(86000000 + index * 137).slice(0, 8)}` : null,
      openingHours: index % 5 === 0 ? '10:30–23:00' : '11:00–22:00',
      markerType: 'image',
      markerImageData: null,
      markerPhotoId: null,
      merchantImageUrl: foodImageUrl(cuisines[cuisineIndex]),
      markerEmoji: emojis[cuisineIndex],
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      isTestData: true,
    })
  })

  const lists: RestaurantListCollection[] = ['适合约会的店', '杭州朋友聚餐', '一个人也舒服', '今年想再去'].map((title, index) => ({
    id: `free-tester-list-${index + 1}`,
    userId: LOCAL_TEST_VIEWER_ID,
    title,
    description: ['安静、有氛围，适合慢慢吃。', '人数多也方便的餐厅。', '一个人也不会尴尬。', '表现稳定，值得再次到访。'][index],
    visibility: index < 2 ? 'public' : 'private',
    isRanked: index === 3,
    coverMode: 'automatic',
    customCoverImageData: null,
    customCoverPhotoId: null,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  }))
  const listItems: RestaurantListItem[] = lists.flatMap((list, listIndex) => Array.from({ length: 6 }, (_, position) => ({
    id: `${list.id}-item-${position + 1}`,
    listId: list.id,
    restaurantId: ids[(listIndex * 7 + position) % 35],
    position,
    note: position === 0 ? '最适合作为这一食单的第一家。' : '',
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  })))

  await db.transaction('rw', db.restaurants, db.visits, db.diningCompanions, db.restaurantLists, db.restaurantListItems, async () => {
    await db.visits.filter((visit) => visit.userId === LOCAL_TEST_VIEWER_ID).delete()
    await db.restaurants.filter((restaurant) => restaurant.userId === LOCAL_TEST_VIEWER_ID).delete()
    await db.diningCompanions.where('ownerUserId').equals(LOCAL_TEST_VIEWER_ID).delete()
    await db.restaurantLists.where('userId').equals(LOCAL_TEST_VIEWER_ID).delete()
    await db.restaurantListItems.where('id').startsWith('free-tester-list-').delete()
    await db.restaurants.bulkPut(restaurants)
    await db.visits.bulkPut(visits)
    await db.diningCompanions.bulkPut(companions)
    await db.restaurantLists.bulkPut(lists)
    await db.restaurantListItems.bulkPut(listItems)
  })
  if (typeof window !== 'undefined') window.localStorage.setItem(storageKey, FREE_TEST_SEED_VERSION)
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

function freeSeedCompanionIds(restaurantIndex: number, visitIndex: number) {
  if (restaurantIndex === 0) return ['free-tester-companion-1']
  if (restaurantIndex === 1 || restaurantIndex === 2) return ['free-tester-companion-2']
  if (restaurantIndex === 3 && visitIndex === 0) return ['free-tester-companion-3']
  if ([20, 21, 22].includes(restaurantIndex)) return ['free-tester-companion-4']
  if ([23, 24].includes(restaurantIndex)) return ['free-tester-companion-5']
  if (restaurantIndex === 4) return ['free-tester-companion-7']
  if (restaurantIndex === 5) return ['free-tester-companion-8']
  if (restaurantIndex % 7 === 0 && visitIndex === 0) return ['free-tester-companion-6']
  return []
}

function privateCompanionAvatarData(label: string, color: string) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160"><rect width="160" height="160" rx="80" fill="${color}"/><circle cx="80" cy="62" r="27" fill="#fff" fill-opacity=".94"/><path d="M32 143c4-34 22-51 48-51s44 17 48 51" fill="#fff" fill-opacity=".94"/><text x="80" y="151" text-anchor="middle" font-family="sans-serif" font-size="20" font-weight="700" fill="${color}">${label}</text></svg>`
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
}

function foodImageUrl(cuisine: string) {
  const images: Record<string, string> = {
    日料: 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?auto=format&fit=crop&w=480&q=78',
    烧烤: 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=480&q=78',
    火锅: 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=480&q=78',
    川菜: 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=480&q=78',
    西餐: 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=480&q=78',
    杭帮菜: 'https://images.unsplash.com/photo-1541544741938-0af808871cc0?auto=format&fit=crop&w=480&q=78',
    粤菜: 'https://images.unsplash.com/photo-1563245372-f21724e3856d?auto=format&fit=crop&w=480&q=78',
    融合菜: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=480&q=78',
  }
  return images[cuisine] ?? images.融合菜
}
