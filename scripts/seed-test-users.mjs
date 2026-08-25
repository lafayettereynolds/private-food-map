import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const action = process.argv[2]
const environment = process.argv[process.argv.indexOf('--environment') + 1]
if (!['seed', 'reset'].includes(action) || environment !== 'development') {
  console.error('测试数据命令只允许使用：seed|reset --environment development')
  process.exit(1)
}

const SEED = process.env.TASTE_MAP_TEST_SEED || 'taste-map-discovery-v1'
const TEST_PREFIX = 'test-discovery-'
const wrangler = join(process.cwd(), 'node_modules', '.bin', process.platform === 'win32' ? 'wrangler.cmd' : 'wrangler')
const random = seededRandom(hashSeed(SEED))
const sql = action === 'reset' ? resetSql() : buildSeedSql()
const temporaryDirectory = mkdtempSync(join(tmpdir(), 'taste-map-test-seed-'))
const sqlFile = join(temporaryDirectory, `${action}.sql`)
const markerDirectory = join(process.cwd(), '.wrangler')
const markerFile = join(markerDirectory, 'taste-map-test-data.seeded')
writeFileSync(sqlFile, sql, 'utf8')

try {
  const result = spawnSync(wrangler, ['d1', 'execute', 'food-map-db', '--local', `--file=${sqlFile}`], {
    cwd: process.cwd(), stdio: 'inherit', shell: process.platform === 'win32',
  })
  if (result.status !== 0) process.exit(result.status ?? 1)
  if (action === 'reset') {
    rmSync(markerFile, { force: true })
    console.log('已清空本机开发 D1 中的发现测试数据；正式数据未触碰。')
  } else {
    mkdirSync(markerDirectory, { recursive: true })
    writeFileSync(markerFile, `${SEED}\n`, 'utf8')
  }
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true })
}

function buildSeedSql() {
  const now = new Date('2026-08-23T08:00:00.000Z')
  const users = buildUsers(now)
  const restaurants = buildRestaurants(now)
  const visits = buildVisits(users, restaurants, now)
  const follows = buildFollows(users, now)
  const friendships = buildFriendships(users, now)
  const wants = buildWantToGo(users, restaurants, now)
  const shared = buildSharedMeals(users, restaurants, visits, now)
  const companions = buildHistoricalCompanions(users, visits, now)
  const statements = [
    'PRAGMA foreign_keys = ON;', 'BEGIN TRANSACTION;', resetSql(false),
    ...restaurants.map(insertRestaurant), ...restaurants.map(updateRestaurantImage), ...users.map(insertUser),
    ...visits.map(insertVisit), ...follows.map(insertFollow),
    ...friendships.map(insertFriendship), ...wants.map(insertWant),
    ...shared.meals.map(insertSharedMeal), ...shared.participants.map(insertParticipant),
    ...companions.rows.map(insertCompanion), ...companions.visitUpdates,
    'COMMIT;',
  ]
  console.log(JSON.stringify({
    seed: SEED, users: users.length, restaurants: restaurants.length, visits: visits.length,
    follows: follows.length, friendships: friendships.length, sharedMeals: shared.meals.length,
    wantToGo: wants.length, historicalCompanionScenarios: companions.rows.length,
  }, null, 2))
  return statements.join('\n')
}

function resetSql(withTransaction = true) {
  const statements = [
    "DELETE FROM companion_link_requests WHERE is_test_data = 1 OR requester_user_id LIKE 'test-discovery-%' OR target_user_id LIKE 'test-discovery-%';",
    "DELETE FROM dining_companions WHERE is_test_data = 1 OR owner_user_id LIKE 'test-discovery-%';",
    'DELETE FROM shared_meal_participants WHERE is_test_data = 1;',
    'DELETE FROM shared_meals WHERE is_test_data = 1;',
    'DELETE FROM want_to_go WHERE is_test_data = 1;',
    'DELETE FROM follows WHERE is_test_data = 1;',
    'DELETE FROM friendships WHERE is_test_data = 1;',
    'DELETE FROM visits WHERE is_test_data = 1;',
    'DELETE FROM restaurants WHERE is_test_data = 1;',
    'DELETE FROM users WHERE is_test_user = 1;',
  ]
  return withTransaction ? ['PRAGMA foreign_keys = ON;', 'BEGIN TRANSACTION;', ...statements, 'COMMIT;'].join('\n') : statements.join('\n')
}

function buildUsers(now) {
  const clusters = [
    ['A', 8, '杭州', ['日料', '烧肉', '咖啡']], ['B', 8, '杭州', ['日料', '杭帮菜', '咖啡']],
    ['C', 8, '杭州', ['火锅', '川菜', '快餐']], ['D', 6, '上海', ['日料', '咖啡', '烧肉', '火锅', '西餐', '甜品']],
    ['E', 6, '东京', ['日料', '西餐', '咖啡']], ['F', 4, '杭州', []],
  ]
  const avatarIds = ['polar-bear', 'penguin', 'cat', 'dog', 'parrot', 'dinosaur', 'shiba', 'panda', 'otter', 'hedgehog', 'rabbit', 'koala', 'fox', 'raccoon', 'deer', 'whale']
  let index = 0
  return clusters.flatMap(([cluster, count, city, preferences]) => Array.from({ length: count }, (_, clusterIndex) => {
    index += 1
    const id = `${TEST_PREFIX}user-${String(index).padStart(2, '0')}`
    return {
      id, cluster, clusterIndex, nickname: `TestUser${String(index).padStart(2, '0')}`,
      city, preferences, avatar: avatarIds[(index - 1) % avatarIds.length],
      createdAt: isoDaysAgo(now, 90 + Math.floor(random() * 620)),
    }
  }))
}

function buildRestaurants(now) {
  const hangzhouNames = [
    '桂满陇·江南小馆（来福士店）', '山葵家精致料理（来福士店）', '浅草君日式烧肉（来福士店）', '椒响川菜（来福士店）',
    '南洋里新加坡料理（来福士店）', '潮上潮汕牛肉锅（来福士店）', '月影铁板烧（来福士店）', '云炉云南菜（来福士店）',
    '金栗韩式烤肉（来福士店）', '鹿港小镇（来福士店）', '拾味融合菜（来福士店）', '海风里海鲜餐厅（来福士店）',
    '小吊梨汤（来福士店）', '樱田寿司（来福士店）', '炙焰牛排馆（来福士店）', '泰香米泰国菜（来福士店）',
    '江户前寿司（来福士店）', '福气粤菜馆（来福士店）', '麦香意面坊（来福士店）', '一炉一会炭火烧鸟（来福士店）',
    '新白鹿餐厅（湖滨银泰店）', '外婆家（湖滨银泰店）', '湖滨里杭帮菜（湖滨银泰店）', '赤坂亭烧肉（湖滨银泰店）',
    '捞王锅物料理（湖滨银泰店）', '西塔老太太泥炉烤肉（湖滨银泰店）', '九本居酒屋（湖滨银泰店）', '山缓缓火锅（湖滨银泰店）',
    '阿嬷手作（湖滨银泰店）', '兰巴赫西餐啤酒坊（湖滨银泰店）', '宴西湖（湖滨银泰店）', '江边城外烤全鱼（湖滨银泰店）',
    '肉本家（湖滨银泰店）', '青花椒砂锅鱼（湖滨银泰店）', '稻香酒家（湖滨银泰店）', '寿喜烧研究所（湖滨银泰店）',
    '马路边边串串香（湖滨银泰店）', '王品牛排（湖滨银泰店）', '和府捞面（湖滨银泰店）', '乐忻皇朝（湖滨银泰店）',
  ]
  const cuisines = ['杭帮菜', '日料', '烧肉', '川菜', '东南亚菜', '火锅', '西餐', '云南菜', '烧肉', '甜品']
  const restaurants = hangzhouNames.map((name, index) => ({
    id: `sample-restaurant-${String(index + 1).padStart(2, '0')}`, name, city: '杭州市',
    amapPoiId: `sample-amap-poi-${String(index + 1).padStart(2, '0')}`,
    address: `${index < 20 ? '来福士中心' : '湖滨银泰'}附近 ${20 + index} 号`,
    latitude: 30.2465 + ((index % 7) - 3) * 0.0013, longitude: 120.19 + ((index % 9) - 4) * 0.0016,
    cuisine: cuisines[index % cuisines.length], isTestData: true,
  }))
  const cityFixtures = [
    ['上海市', 31.2304, 121.4737, ['静安寿司小院', '徐汇咖啡实验室', '浦东炭火烧肉', '虹口川味馆', '法租界西餐厅', '黄浦甜品所']],
    ['北京市', 39.9042, 116.4074, ['三里屯烧鸟', '国贸咖啡社', '簋街火锅馆', '胡同京菜馆', '朝阳西餐室', '鼓楼甜品铺']],
    ['东京', 35.6762, 139.6503, ['银座鮨一', '代官山咖啡', '新宿烧肉屋', '浅草天妇罗', '涩谷洋食堂', '表参道甜品店']],
    ['大阪', 34.6937, 135.5023, ['难波寿司', '心斋桥咖啡', '梅田烧肉', '道顿堀章鱼烧']],
    ['香港', 22.3193, 114.1694, ['中环茶餐厅', '上环咖啡室', '尖沙咀烧味', '铜锣湾甜品']],
  ]
  let extraIndex = 0
  cityFixtures.forEach(([city, latitude, longitude, names]) => names.forEach((name, index) => {
    extraIndex += 1
    restaurants.push({
      id: `${TEST_PREFIX}restaurant-${String(extraIndex).padStart(2, '0')}`, name, city,
      amapPoiId: `seed-poi-${TEST_PREFIX}restaurant-${String(extraIndex).padStart(2, '0')}`,
      address: `${city}测试街区 ${index + 1} 号`, latitude: Number(latitude) + index * 0.003,
      longitude: Number(longitude) + index * 0.003, cuisine: ['日料', '咖啡', '烧肉', '火锅', '西餐', '甜品'][index % 6], isTestData: true,
    })
  }))
  return restaurants.map((item, index) => ({
    ...item,
    phone: `0571-${String(87000000 + index * 191).slice(0, 8)}`,
    openingHours: index % 6 === 0 ? '10:30–23:00' : '11:00–22:00',
    createdAt: isoDaysAgo(now, 760),
  }))
}

function buildVisits(users, restaurants, now) {
  const clusterRanges = { A: [35, 55], B: [25, 45], C: [12, 30], D: [45, 70], E: [20, 40], F: [0, 2] }
  const trending = new Set(['sample-restaurant-03', 'sample-restaurant-14', 'sample-restaurant-29', `${TEST_PREFIX}restaurant-13`, `${TEST_PREFIX}restaurant-15`, `${TEST_PREFIX}restaurant-18`])
  const cooling = new Set(['sample-restaurant-01', 'sample-restaurant-21', 'sample-restaurant-25', 'sample-restaurant-31'])
  const visits = []
  const ownerPreferences = new Set(['日料', '烧肉', '咖啡'])
  const ownerRestaurants = restaurants.filter((restaurant) => restaurant.city === '杭州市').slice(0, 32)
  for (let index = 0; index < 24; index += 1) {
    const restaurant = ownerRestaurants[(index * 5) % ownerRestaurants.length]
    const totalPrice = 90 + Math.floor(random() * 420)
    const partySize = 1 + Math.floor(random() * 4)
    visits.push({
      id: `${TEST_PREFIX}owner-visit-${String(index + 1).padStart(2, '0')}`,
      userId: 'owner', restaurantId: restaurant.id, visitedAt: isoDaysAgo(now, 40 + index * 18),
      rating: clampHalf((ownerPreferences.has(restaurant.cuisine) ? 4.55 : 3.65) + (random() - 0.5) * 0.8),
      visibility: 'private', diningMode: index % 6 === 0 ? 'takeout' : 'dine_in', totalPrice, partySize,
      note: index % 5 === 0 ? noteFor(restaurant.cuisine, ownerPreferences.has(restaurant.cuisine)) : '',
    })
  }
  users.forEach((user) => {
    let count
    if (user.cluster === 'F') count = user.clusterIndex < 2 ? 0 : user.clusterIndex === 2 ? 2 : 0
    else {
      const [min, max] = clusterRanges[user.cluster]
      count = min + Math.floor(random() * (max - min + 1))
    }
    const preferred = restaurants.filter((restaurant) => user.preferences.includes(restaurant.cuisine))
    const available = user.cluster === 'E' ? restaurants : restaurants.filter((restaurant) => restaurant.city === '杭州市' || random() < 0.1)
    for (let index = 0; index < count; index += 1) {
      const restaurant = random() < 0.7 && preferred.length ? preferred[Math.floor(random() * preferred.length)] : available[Math.floor(random() * available.length)]
      const isTrending = trending.has(restaurant.id)
      const isCooling = cooling.has(restaurant.id)
      const daysAgo = isTrending && random() < 0.48 ? Math.floor(random() * 7)
        : isCooling ? 45 + Math.floor(random() * 600)
          : random() < 0.22 ? Math.floor(random() * 30) : 31 + Math.floor(random() * 680)
      const preference = user.preferences.includes(restaurant.cuisine)
      const baseScore = preference ? 4.45 : user.cluster === 'C' ? 3.35 : 3.75
      const rating = clampHalf(baseScore + (random() - 0.5) * 1.5)
      const visibilityRoll = random()
      const visibility = visibilityRoll < 0.55 ? 'public' : visibilityRoll < 0.8 ? 'friends' : 'private'
      const visitedAt = isoDaysAgo(now, daysAgo, Math.floor(random() * 14))
      visits.push({
        id: `${TEST_PREFIX}visit-${user.id.slice(-2)}-${String(index + 1).padStart(3, '0')}`,
        userId: user.id, restaurantId: restaurant.id, visitedAt, rating, visibility,
        diningMode: random() < 0.18 ? 'takeout' : 'dine_in', totalPrice: 40 + Math.floor(random() * 560),
        partySize: 1 + Math.floor(random() * 5), note: random() < 0.35 ? noteFor(restaurant.cuisine, preference) : '',
      })
    }
  })
  return visits
}

function buildFollows(users, now) {
  const rows = []
  const ownerTargets = [...users.filter((u) => u.cluster === 'A').slice(0, 5), ...users.filter((u) => u.cluster === 'B').slice(0, 3), ...users.filter((u) => u.cluster === 'C').slice(0, 2)]
  ownerTargets.forEach((target) => rows.push(followRow('owner', target.id, now)))
  // Give the owner both inbound-only and mutual relationships so the profile
  // can exercise “关注我的 / 我关注的” without relying on production accounts.
  const ownerFollowers = [
    ...users.filter((u) => u.cluster === 'A').slice(0, 2),
    ...users.filter((u) => u.cluster === 'C').slice(2, 5),
    ...users.filter((u) => u.cluster === 'E').slice(0, 4),
  ]
  ownerFollowers.forEach((source) => rows.push(followRow(source.id, 'owner', now)))
  users.forEach((user, index) => {
    const count = 2 + (index % 5)
    for (let offset = 1; offset <= count; offset += 1) {
      const target = users[(index + offset * 3) % users.length]
      if (target.id !== user.id) rows.push(followRow(user.id, target.id, now))
    }
  })
  return uniqueBy(rows, (row) => `${row.followerId}:${row.followedUserId}`)
}

function buildFriendships(users, now) {
  const accepted = [...users.filter((u) => u.cluster === 'A').slice(0, 3), ...users.filter((u) => u.cluster === 'B').slice(0, 2), users.find((u) => u.cluster === 'C'), users.find((u) => u.cluster === 'D')].filter(Boolean)
  const rows = accepted.map((target) => friendshipRow('owner', target.id, 'accepted', now))
  rows.push(friendshipRow('owner', users.find((u) => u.cluster === 'E').id, 'pending', now))
  rows.push(friendshipRow(users.find((u) => u.cluster === 'C' && u.clusterIndex === 1).id, 'owner', 'rejected', now))
  users.slice(0, 20).forEach((user, index) => rows.push(friendshipRow(user.id, users[(index + 7) % users.length].id, 'accepted', now)))
  return uniqueBy(rows, (row) => [row.requesterId, row.addresseeId].sort().join(':'))
}

function buildWantToGo(users, restaurants, now) {
  return users.flatMap((user) => {
    const count = user.cluster === 'F' && user.clusterIndex === 3 ? 18 : 5 + Math.floor(random() * 26)
    return shuffled(restaurants).slice(0, count).map((restaurant, index) => ({
      id: `${TEST_PREFIX}want-${user.id.slice(-2)}-${String(index + 1).padStart(2, '0')}`,
      userId: user.id, restaurantId: restaurant.id, createdAt: isoDaysAgo(now, Math.floor(random() * 220)),
    }))
  })
}

function buildSharedMeals(users, restaurants, visits, now) {
  const meals = []
  const participants = []
  for (let index = 0; index < 36; index += 1) {
    const first = users[index % 24]
    const second = users[(index * 5 + 3) % 30]
    const firstVisits = visits.filter((visit) => visit.userId === first.id)
    if (!firstVisits.length) continue
    const firstVisit = firstVisits[index % firstVisits.length]
    const id = `${TEST_PREFIX}meal-${String(index + 1).padStart(2, '0')}`
    meals.push({ id, restaurantId: firstVisit.restaurantId, creator: first.id, occurredAt: firstVisit.visitedAt })
    participants.push(participantRow(id, first.id, firstVisit.id, index, now))
    const secondVisit = visits.find((visit) => visit.userId === second.id && visit.restaurantId === firstVisit.restaurantId) ?? null
    participants.push(participantRow(id, second.id, secondVisit?.id ?? null, index + 100, now))
    firstVisit.sharedMealId = id
    if (secondVisit) secondVisit.sharedMealId = id
  }
  return { meals, participants }
}

function buildHistoricalCompanions(users, visits, now) {
  const scenarios = [
    [users[0], users[22], '小王', 12], [users[1], users[27], '阿宁', 8], [users[2], users[31], '小林', 6],
  ]
  const rows = []
  const visitUpdates = []
  scenarios.forEach(([owner, target, displayName, count], scenarioIndex) => {
    const id = `${TEST_PREFIX}companion-${scenarioIndex + 1}`
    rows.push({ id, ownerUserId: owner.id, displayName, createdAt: now.toISOString(), targetUserId: target.id })
    visits.filter((visit) => visit.userId === owner.id).slice(0, count).forEach((visit) => {
      visitUpdates.push(`UPDATE visits SET companions_json = ${q(JSON.stringify([displayName]))}, companion_ids_json = ${q(JSON.stringify([id]))} WHERE id = ${q(visit.id)};`)
    })
  })
  return { rows, visitUpdates }
}

function insertRestaurant(r) { return `INSERT INTO restaurants (id,user_id,amap_poi_id,name,address,city,latitude,longitude,status,preference_level,tags_json,long_term_note,phone,opening_hours,marker_type,merchant_image_url,marker_emoji,created_at,updated_at,is_test_data) VALUES (${q(r.id)},'owner',${q(r.amapPoiId)},${q(r.name)},${q(r.address)},${q(r.city)},${r.latitude},${r.longitude},'visited','normal',${q(JSON.stringify([r.cuisine]))},'',${q(r.phone)},${q(r.openingHours)},'image',${q(foodImageUrl(r.cuisine))},'🍽️',${q(r.createdAt)},${q(r.createdAt)},${r.isTestData ? 1 : 0}) ON CONFLICT(id) DO UPDATE SET amap_poi_id=excluded.amap_poi_id,name=excluded.name,address=excluded.address,city=excluded.city,latitude=excluded.latitude,longitude=excluded.longitude,tags_json=excluded.tags_json,phone=excluded.phone,opening_hours=excluded.opening_hours,merchant_image_url=excluded.merchant_image_url,is_test_data=1;` }
function updateRestaurantImage(r) { return `UPDATE restaurants SET merchant_image_url = COALESCE(merchant_image_url, ${q(foodImageUrl(r.cuisine))}) WHERE id = ${q(r.id)};` }

function foodImageUrl(cuisine) {
  const images = {
    '日料': 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?auto=format&fit=crop&w=320&q=75',
    '烧肉': 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=320&q=75',
    '咖啡': 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=320&q=75',
    '火锅': 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=320&q=75',
    '面食': 'https://images.unsplash.com/photo-1555126634-323283e090fa?auto=format&fit=crop&w=320&q=75',
  }
  return images[cuisine] ?? 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=320&q=75'
}
function insertUser(u) { return `INSERT INTO users (id,auth_provider,nickname,bio,city,avatar_preset_id,membership_tier,map_sharing_enabled,map_visibility,created_at,updated_at,is_test_user) VALUES (${q(u.id)},'local',${q(u.nickname)},${q(`测试口味组 ${u.cluster}`)},${q(u.city)},${q(u.avatar)},'free',1,'public',${q(u.createdAt)},${q(u.createdAt)},1);` }
function insertVisit(v) {
  const ppp = Math.round(v.totalPrice / v.partySize)
  const variant = hashSeed(v.id) % 4
  const sources = ['friend', 'xiaohongshu', 'dianping', 'self']
  const sourceLabels = ['好友推荐', '小红书收藏', '大众点评', '自己发现']
  const occasions = ['friends', 'date', 'family', 'solo']
  const valueTags = ['合理', '超值', '划算', '偏贵']
  const environmentTags = ['舒适', '有氛围', '安静', '热闹']
  const serviceTags = ['周到', '专业', '高效', '热情']
  const specialNotes = variant === 2 ? '周末高峰建议提前到店。' : ''
  return `INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,total_price,price_per_person,party_size,queue_duration,companions_json,dishes_json,note,created_at,updated_at,visibility,dining_mode,my_actual_spend,special_notes,shared_meal_id,photo_ids_json,value_rating,environment_rating,service_rating,value_tags_json,environment_tags_json,service_tags_json,dining_occasions_json,recommendation_source_type,recommendation_source_text,noise_level,dining_duration,portion_level,transport_convenience,companion_ids_json,is_test_data) VALUES (${q(v.id)},${q(v.userId)},${q(v.restaurantId)},${q(v.visitedAt)},${v.rating},${v.totalPrice},${ppp},${v.partySize},'under30','[]','[]',${q(v.note)},${q(v.visitedAt)},${q(v.visitedAt)},${q(v.visibility)},${q(v.diningMode)},${ppp},${q(specialNotes)},${q(v.sharedMealId ?? null)},'[]',${v.rating},${Math.max(2.5, v.rating - 0.5)},${Math.min(5, v.rating + 0.5)},${q(JSON.stringify([valueTags[variant]]))},${q(JSON.stringify([environmentTags[variant]]))},${q(JSON.stringify([serviceTags[variant]]))},${q(JSON.stringify([occasions[variant]]))},${q(sources[variant])},${q(sourceLabels[variant])},${q(['quiet','normal','loud','normal'][variant])},${q(['under30','under45','under60','under90'][variant])},${q(['normal','generous','normal','small'][variant])},${q(['very_convenient','convenient','normal','convenient'][variant])},'[]',1);`
}
function insertFollow(v) { return `INSERT INTO follows (id,follower_id,followed_user_id,created_at,is_test_data) VALUES (${q(v.id)},${q(v.followerId)},${q(v.followedUserId)},${q(v.createdAt)},1);` }
function insertFriendship(v) { return `INSERT INTO friendships (id,requester_id,addressee_id,status,created_at,updated_at,is_test_data) VALUES (${q(v.id)},${q(v.requesterId)},${q(v.addresseeId)},${q(v.status)},${q(v.createdAt)},${q(v.createdAt)},1);` }
function insertWant(v) { return `INSERT INTO want_to_go (id,user_id,restaurant_id,created_at,is_test_data) VALUES (${q(v.id)},${q(v.userId)},${q(v.restaurantId)},${q(v.createdAt)},1);` }
function insertSharedMeal(v) { return `INSERT INTO shared_meals (id,restaurant_id,created_by_user_id,occurred_at,created_at,updated_at,is_test_data) VALUES (${q(v.id)},${q(v.restaurantId)},${q(v.creator)},${q(v.occurredAt)},${q(v.occurredAt)},${q(v.occurredAt)},1);` }
function insertParticipant(v) { return `INSERT INTO shared_meal_participants (id,shared_meal_id,user_id,visit_id,status,created_at,updated_at,is_test_data) VALUES (${q(v.id)},${q(v.mealId)},${q(v.userId)},${q(v.visitId)},'accepted',${q(v.createdAt)},${q(v.createdAt)},1);` }
function insertCompanion(v) { return `INSERT INTO dining_companions (id,owner_user_id,display_name,linked_user_id,created_at,updated_at,is_test_data) VALUES (${q(v.id)},${q(v.ownerUserId)},${q(v.displayName)},NULL,${q(v.createdAt)},${q(v.createdAt)},1);` }

function followRow(followerId, followedUserId, now) { return { id: `${TEST_PREFIX}follow-${followerId.replace(TEST_PREFIX, '')}-${followedUserId.replace(TEST_PREFIX, '')}`, followerId, followedUserId, createdAt: isoDaysAgo(now, Math.floor(random() * 240)) } }
function friendshipRow(requesterId, addresseeId, status, now) { return { id: `${TEST_PREFIX}friend-${requesterId.replace(TEST_PREFIX, '')}-${addresseeId.replace(TEST_PREFIX, '')}`, requesterId, addresseeId, status, createdAt: isoDaysAgo(now, Math.floor(random() * 180)) } }
function participantRow(mealId, userId, visitId, index, now) { return { id: `${mealId}-participant-${index}`, mealId, userId, visitId, createdAt: now.toISOString() } }
function noteFor(cuisine, liked) { return liked ? `${cuisine}很合口味，愿意再来。` : `体验有亮点，但不是我最偏爱的${cuisine}。` }
function isoDaysAgo(now, days, hour = 12) { const value = new Date(now); value.setUTCDate(value.getUTCDate() - days); value.setUTCHours(hour, 0, 0, 0); return value.toISOString() }
function clampHalf(value) { return Math.max(2.5, Math.min(5, Math.round(value * 2) / 2)) }
function q(value) { return value == null ? 'NULL' : `'${String(value).replaceAll("'", "''")}'` }
function uniqueBy(items, key) { const seen = new Set(); return items.filter((item) => { const value = key(item); if (seen.has(value)) return false; seen.add(value); return true }) }
function shuffled(items) { return [...items].sort(() => random() - 0.5) }
function hashSeed(value) { let hash = 2166136261; for (const char of value) { hash ^= char.charCodeAt(0); hash = Math.imul(hash, 16777619) } return hash >>> 0 }
function seededRandom(seed) { let state = seed >>> 0; return () => { state += 0x6d2b79f5; let value = state; value = Math.imul(value ^ value >>> 15, value | 1); value ^= value + Math.imul(value ^ value >>> 7, value | 61); return ((value ^ value >>> 14) >>> 0) / 4294967296 } }
