const NAMESPACE = 'tm_demo_v2'
const ADMIN_USER_ID = `${NAMESPACE}_admin`
const USER_PREFIX = `${NAMESPACE}_user_`
const PLACE_PREFIX = `${NAMESPACE}_place_`

const CUISINES = [
  '日料', '咖啡', '江浙菜', 'Bistro', '川菜', '粤菜', '火锅', '烧烤', '韩餐',
  '东南亚', '西餐', 'Brunch', 'Fine Dining', '面馆', '小吃', '甜品', 'Bakery', 'Bar food',
]
const CURRENT_PREFERENCES = new Set(['日料', '咖啡', '江浙菜', 'Bistro'])
const AVATARS = [
  'polar-bear', 'penguin', 'cat', 'dog', 'parrot', 'dinosaur', 'shiba', 'panda',
  'otter', 'hedgehog', 'rabbit', 'koala', 'fox', 'raccoon', 'deer', 'whale',
]
const RECOMMENDATION_SOURCES = [
  ['朋友推荐', 'friend'], ['小红书', 'xiaohongshu'], ['大众点评', 'dianping'],
  ['自己发现', 'self'], ['短视频收藏', 'douyin'], ['美食博主', 'blogger'],
  ['散步偶遇', 'other'], ['同事推荐', 'friend'], ['旅行清单', 'other'],
  ['社区讨论', 'other'], ['家人推荐', 'friend'], ['菜单灵感', 'other'],
]
const COMPANION_NAMES = ['阿宁', '小林', '小周', '小满', '安安', '小北', 'Mika', 'Leo', '家人']
const SYNTHETIC_PREFIXES = [
  '雾蓝', '青禾', '月白', '山岚', '浅潮', '星屿', '松影', '风铃', '云栖', '澄野',
  '微光', '听雨', '白桦', '北岸', '南枝', '晴川', '鹿鸣', '浮光', '夏庭', '冬青',
]
const SYNTHETIC_SUFFIXES = [
  '食研所', '小食堂', '料理室', '餐桌', '味觉站', '厨房', '饭局', '食集', '小馆', '食作坊',
]

export const DEVELOPMENT_DEMO_NAMESPACE = NAMESPACE
export const DEVELOPMENT_DEMO_ADMIN_USER_ID = ADMIN_USER_ID
export const DEVELOPMENT_DEMO_USER_PREFIX = USER_PREFIX
export const DEVELOPMENT_DEMO_PLACE_PREFIX = PLACE_PREFIX

export function normalizedReferenceNow(value = new Date()) {
  const parsed = new Date(value)
  if (!Number.isFinite(parsed.getTime())) throw new Error('Development demo referenceNow is invalid.')
  const day = parsed.toISOString().slice(0, 10)
  return new Date(`${day}T12:00:00.000Z`)
}

export function buildDevelopmentDemoDataset({
  currentUserID,
  referenceNow = new Date(),
} = {}) {
  if (!validCurrentUserID(currentUserID)) {
    throw new Error('A non-demo Development current user ID is required.')
  }
  const now = normalizedReferenceNow(referenceNow)
  const day = now.toISOString().slice(0, 10)
  const places = buildRestaurantUniverse(now)
  const currentManifest = buildCurrentUserManifest(currentUserID, places, now)
  const demoUsers = buildDemoUsers(now).map((persona) =>
    buildDemoUserManifest(persona, places, currentManifest.visitedPlaceIDs, now))
  const relationships = buildRelationships(currentUserID, demoUsers, now)
  const allAccounts = [currentManifest, ...demoUsers]
  const summary = summarizeDataset(places, currentManifest, demoUsers, relationships, now)

  return {
    schemaVersion: 1,
    namespace: NAMESPACE,
    referenceDay: day,
    referenceNow: now.toISOString(),
    currentUserID,
    adminUserID: ADMIN_USER_ID,
    places,
    currentUser: currentManifest,
    demoUsers,
    relationships,
    accounts: allAccounts,
    summary,
  }
}

export function entityMutation(record, referenceDay, baseVersion = 0) {
  const revisionTag = String(baseVersion).padStart(4, '0')
  return {
    mutationId: `${NAMESPACE}_seed_${referenceDay}_${record.entityType}_${shortHash(record.entityID)}_v${revisionTag}`,
    entityType: record.entityType,
    entityId: record.entityID,
    operation: 'upsert',
    baseVersion,
    clientTimestamp: record.payload.updatedAt,
    payload: record.payload,
  }
}

export function deleteMutation(entityType, entityID, baseVersion, timestamp) {
  return {
    mutationId: `${NAMESPACE}_clear_${entityType}_${shortHash(entityID)}_v${String(baseVersion).padStart(4, '0')}`,
    entityType,
    entityId: entityID,
    operation: 'delete',
    baseVersion,
    clientTimestamp: timestamp,
  }
}

function buildRestaurantUniverse(now) {
  const cityPlan = [
    ['杭州', 207, 30.2741, 120.1551],
    ['上海', 36, 31.2304, 121.4737],
    ['北京', 18, 39.9042, 116.4074],
    ['成都', 18, 30.5728, 104.0668],
    ['广州', 18, 23.1291, 113.2644],
    ['东京', 18, 35.6762, 139.6503],
    ['大阪', 18, 34.6937, 135.5023],
    ['南京', 9, 32.0603, 118.7969],
    ['厦门', 9, 24.4798, 118.0894],
    ['首尔', 9, 37.5665, 126.9780],
  ]
  const places = []
  for (const [city, count, latitude, longitude] of cityPlan) {
    for (let localIndex = 0; localIndex < count; localIndex += 1) {
      const index = places.length
      const number = index + 1
      const cuisine = CUISINES[index % CUISINES.length]
      const popularity = index < 40 ? 'high' : index < 170 ? 'medium' : 'niche'
      const prefix = SYNTHETIC_PREFIXES[index % SYNTHETIC_PREFIXES.length]
      const suffix = SYNTHETIC_SUFFIXES[Math.floor(index / SYNTHETIC_PREFIXES.length) % SYNTHETIC_SUFFIXES.length]
      const externalID = `${PLACE_PREFIX}${String(number).padStart(3, '0')}`
      places.push({
        id: externalID,
        externalID,
        globalKey: `manual:${externalID}`,
        name: `${prefix}${cuisine}${suffix} · 虚构${String(number).padStart(3, '0')}`,
        address: `${city}开发样本路 ${String(localIndex + 1).padStart(3, '0')} 号（虚构）`,
        city,
        latitude: latitude + ((localIndex % 17) - 8) * 0.0021,
        longitude: longitude + ((localIndex % 19) - 9) * 0.0023,
        cuisine,
        popularity,
        createdAt: daysAgo(now, 760 - (index % 360)),
        trendCohort: index < 12 ? 'strong7d'
          : index < 37 ? 'medium7d'
            : index < 57 ? 'stable30d'
              : index < 69 ? 'historical'
                : 'baseline',
      })
    }
  }
  return places
}

function buildDemoUsers(now) {
  const cities = ['杭州', '杭州', '上海', '杭州', '东京', '成都', '广州', '北京', '大阪', '南京']
  const generous = new Set([1, 2, 5, 9, 14, 18, 23, 29, 34, 41])
  const sparseRating = new Set([43, 44, 45, 46, 47, 48, 49, 50])
  const strict = new Set([7, 12, 16, 20, 24, 28, 31, 33, 35, 37, 39, 42])
  return Array.from({ length: 50 }, (_, offset) => {
    const index = offset + 1
    const tier = index <= 8 ? 'heavy' : index <= 30 ? 'normal' : index <= 42 ? 'light' : 'sparse'
    const similarityGroup = index <= 8 ? 'S' : index <= 16 ? 'A' : index <= 26 ? 'B'
      : index <= 36 ? 'C' : index <= 42 ? 'D' : 'E'
    const visitCount = tier === 'heavy' ? 160 + offset * 5
      : tier === 'normal' ? 93 + ((index - 9) % 11) * 3
        : tier === 'light' ? 40 + ((index - 31) % 12) * 2
          : 3 + (index - 43) * 3
    const restaurantCount = tier === 'heavy' ? 98 - index * 2
      : tier === 'normal' ? 50 + (index % 9) * 3
        : tier === 'light' ? 23 + (index % 8) * 3
          : Math.min(20, 3 + (index - 43) * 2)
    const wantCount = tier === 'heavy' ? 24 + (index % 5) * 4
      : tier === 'normal' ? 16 + (index % 7) * 2
        : tier === 'light' ? 15 + (index % 4) * 3
          : 3 + (index % 5) * 3
    const ratingPersona = sparseRating.has(index) ? 'sparse'
      : generous.has(index) ? 'generous'
        : strict.has(index) ? 'strict' : 'balanced'
    const spendPersona = ['budget', 'mid', 'premium', 'mixed'][(index - 1) % 4]
    const preferences = preferencesForGroup(similarityGroup, index)
    const profileVisibility = index <= 15 ? 'public'
      : index <= 30 ? (index % 4 === 0 ? 'friends' : 'public')
        : index <= 42 ? (index % 3 === 0 ? 'private' : 'friends')
          : index % 2 === 0 ? 'private' : 'public'
    return {
      id: `${USER_PREFIX}${String(index).padStart(2, '0')}`,
      index,
      tier,
      similarityGroup,
      visitCount,
      restaurantCount: Math.min(restaurantCount, visitCount),
      wantCount,
      ratingPersona,
      spendPersona,
      city: cities[(index - 1) % cities.length],
      preferences,
      profileVisibility,
      displayName: `Taste Map Demo ${String(index).padStart(2, '0')}`,
      joinedAt: daysAgo(now, 850 - index * 11),
    }
  })
}

function buildCurrentUserManifest(currentUserID, places, now) {
  const ownerHash = shortHash(currentUserID)
  const prefix = `${NAMESPACE}_current_${ownerHash}`
  const preferred = rankedPlaces(places, 'current', (place) =>
    (CURRENT_PREFERENCES.has(place.cuisine) ? 1_000 : 0) +
    (place.city === '杭州' ? 300 : 0) + popularityWeight(place.popularity))
  const visitedPlaces = preferred.slice(0, 90)
  const wantedPlaces = preferred.filter((place) => !visitedPlaces.includes(place)).slice(0, 28)
  return buildAccountManifest({
    ownerID: currentUserID,
    prefix,
    index: 0,
    tier: 'current',
    similarityGroup: 'CURRENT',
    ratingPersona: 'balanced',
    spendPersona: 'mixed',
    city: '杭州',
    preferences: [...CURRENT_PREFERENCES],
    visitedPlaces,
    wantedPlaces,
    visitCount: 275,
    listCount: 5,
    sourceCount: 11,
    companionCount: 9,
    profile: null,
    now,
  })
}

function buildDemoUserManifest(persona, places, currentVisitedPlaceIDs, now) {
  const currentVisited = places.filter((place) => currentVisitedPlaceIDs.includes(place.id))
  const overlapTargets = { S: persona.index === 1 ? 84 : persona.index === 2 ? 80 : 68, A: 46, B: 29, C: 10, D: 3, E: 2 }
  const targetOverlap = Math.min(overlapTargets[persona.similarityGroup], persona.restaurantCount)
  const overlap = rankedPlaces(currentVisited, `${persona.id}:overlap`, (place) =>
    (persona.preferences.includes(place.cuisine) ? 800 : 0) + popularityWeight(place.popularity))
    .slice(0, targetOverlap)
  const selected = new Map(overlap.map((place) => [place.id, place]))

  // Real raw events, not precomputed scores: strong cohort places receive 15–30
  // distinct visitors, medium cohort places receive 5–12.
  for (const place of places.filter((item) => item.trendCohort === 'strong7d')) {
    if (persona.index <= 30 && (persona.index + numericSuffix(place.id)) % 3 !== 0) selected.set(place.id, place)
  }
  for (const place of places.filter((item) => item.trendCohort === 'medium7d')) {
    if ((persona.index * 3 + numericSuffix(place.id)) % 7 === 0) selected.set(place.id, place)
  }
  for (const place of places.filter((item) => item.trendCohort === 'stable30d')) {
    if ((persona.index * 2 + numericSuffix(place.id)) % 5 === 0) selected.set(place.id, place)
  }
  for (const place of places.filter((item) => item.trendCohort === 'historical')) {
    if (persona.index <= 28 && (persona.index * 3 + numericSuffix(place.id)) % 4 === 0) selected.set(place.id, place)
  }

  const candidates = rankedPlaces(places, `${persona.id}:fill`, (place) =>
    (persona.preferences.includes(place.cuisine) ? 900 : 0) +
    (place.city === persona.city ? 180 : 0) + popularityWeight(place.popularity))
  for (const place of candidates) {
    if (selected.size >= persona.restaurantCount) break
    selected.set(place.id, place)
  }
  while (selected.size > persona.restaurantCount) {
    const removable = [...selected.values()].reverse().find((place) => !overlap.some((item) => item.id === place.id))
    if (!removable) break
    selected.delete(removable.id)
  }
  const visitedPlaces = [...selected.values()]
  const wantedPlaces = rankedPlaces(
    places.filter((place) => !selected.has(place.id)),
    `${persona.id}:want`,
    (place) => (persona.preferences.includes(place.cuisine) ? 400 : 0) + popularityWeight(place.popularity),
  ).slice(0, persona.wantCount)
  const listCount = persona.tier === 'heavy' ? 4
    : persona.tier === 'normal' ? 2
      : persona.tier === 'light' && persona.index <= 38 ? 1 : 0
  const sourceCount = persona.tier === 'sparse' ? 2 : persona.tier === 'light' ? 3 : 5
  const companionCount = persona.tier === 'heavy' ? 4 : persona.tier === 'normal' ? 3 : persona.tier === 'light' ? 2 : 0
  return buildAccountManifest({
    ownerID: persona.id,
    prefix: `${NAMESPACE}_u${String(persona.index).padStart(2, '0')}`,
    ...persona,
    visitedPlaces,
    wantedPlaces,
    listCount,
    sourceCount,
    companionCount,
    profile: {
      displayName: persona.displayName,
      bio: `${persona.city}的虚拟美食记录者 · ${persona.tier} 样本`,
      city: persona.city,
      avatarPresetId: AVATARS[(persona.index - 1) % AVATARS.length],
      visibility: persona.profileVisibility,
      createdAt: persona.joinedAt,
    },
    now,
  })
}

function buildAccountManifest(options) {
  const {
    ownerID, prefix, index, tier, similarityGroup, ratingPersona, spendPersona,
    city, preferences, visitedPlaces, wantedPlaces, visitCount, listCount,
    sourceCount, companionCount, profile, now,
  } = options
  const records = []
  const restaurantByPlace = new Map()
  const profileRecord = profile ? makeProfileRecord(ownerID, profile, now) : null
  if (profileRecord) records.push(profileRecord)

  const recommendationSources = RECOMMENDATION_SOURCES.slice(0, sourceCount).map(([name, type], sourceIndex) => {
    const entityID = `${prefix}_source_${String(sourceIndex + 1).padStart(2, '0')}`
    const timestamp = daysAgo(now, 500 - sourceIndex * 23)
    const record = recordOf('recommendationSource', entityID, {
      schemaVersion: 1, id: entityID, userId: ownerID, displayName: name,
      sourceType: type, linkedTasteMapUserId: null,
      createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
    })
    records.push(record)
    return record.payload
  })
  const companions = COMPANION_NAMES.slice(0, companionCount).map((name, companionIndex) => {
    const entityID = `${prefix}_companion_${String(companionIndex + 1).padStart(2, '0')}`
    const timestamp = daysAgo(now, 420 - companionIndex * 17)
    const record = recordOf('companion', entityID, {
      schemaVersion: 1, id: entityID, userId: ownerID, displayName: name,
      linkedTasteMapUserId: null, createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
    })
    records.push(record)
    return record.payload
  })

  ;[...visitedPlaces, ...wantedPlaces].forEach((place, restaurantIndex) => {
    const status = restaurantIndex < visitedPlaces.length ? 'visited' : 'wantToGo'
    const entityID = `${prefix}_restaurant_${String(restaurantIndex + 1).padStart(3, '0')}`
    const timestamp = daysAgo(now, 650 - (restaurantIndex % 500))
    const restaurant = makeRestaurantRecord(ownerID, entityID, place, status, timestamp, ratingPersona, spendPersona)
    restaurantByPlace.set(place.id, restaurant.payload)
    records.push(restaurant)
  })

  const visits = []
  const dishes = []
  const visitDishes = []
  for (let visitIndex = 0; visitIndex < visitCount; visitIndex += 1) {
    const place = visitedPlaces[visitIndex % visitedPlaces.length]
    const restaurant = restaurantByPlace.get(place.id)
    const visitedAt = visitTimestamp(now, place, index, visitIndex)
    const rating = ratingFor(ratingPersona, preferences.includes(place.cuisine), `${ownerID}:rating:${visitIndex}`)
    const visibility = visibilityFor(index, tier, visitIndex)
    const source = recommendationSources.length ? recommendationSources[visitIndex % recommendationSources.length] : null
    const selectedCompanions = companions.length && visitIndex % 3 === 0
      ? [companions[visitIndex % companions.length]] : []
    const partySize = 1 + (hash32(`${ownerID}:party:${visitIndex}`) % 5)
    const amount = spendFor(spendPersona, place.cuisine, `${ownerID}:spend:${visitIndex}`)
    const visitID = `${prefix}_visit_${String(visitIndex + 1).padStart(4, '0')}`
    const visit = recordOf('visit', visitID, {
      schemaVersion: 1, id: visitID, userId: ownerID, restaurantId: restaurant.id,
      visitedAt, diningMode: visitIndex % 9 === 0 ? 'takeout' : 'dine_in', visibility,
      partySize, totalPrice: amount.perPerson * partySize,
      paymentMode: ['self', 'split', 'host', null][visitIndex % 4], pricePerPerson: amount.perPerson,
      queueDuration: ['none', 'under15', 'under30', 'under60', null][visitIndex % 5],
      diningOccasions: [['solo'], ['friends'], ['date'], ['family']][visitIndex % 4],
      diningOccasionText: null, rating,
      valueRating: rating === null ? null : clampHalf(rating + ((visitIndex % 3) - 1) * 0.5),
      environmentRating: rating === null ? null : clampHalf(rating + ((visitIndex % 2) ? 0.5 : 0)),
      serviceRating: rating === null ? null : clampHalf(rating - ((visitIndex % 4 === 0) ? 0.5 : 0)),
      valueTags: visitIndex % 3 === 0 ? ['价格合理'] : [],
      environmentTags: visitIndex % 4 === 0 ? ['有生活感'] : [],
      serviceTags: visitIndex % 5 === 0 ? ['响应及时'] : [],
      noiseLevel: ['quiet', 'normal', 'loud', null][visitIndex % 4],
      diningDuration: ['under45', 'under60', 'under90', null][visitIndex % 4],
      portionLevel: ['small', 'normal', 'generous', null][visitIndex % 4],
      transportConvenience: ['very_convenient', 'convenient', 'normal', null][visitIndex % 4],
      specialNotes: visitIndex % 17 === 0 ? '虚拟样本：高峰期可能需要等位。' : null,
      companions: selectedCompanions.map((item) => item.displayName),
      companionIds: selectedCompanions.map((item) => item.id),
      recommendationSourceId: source?.id ?? null,
      recommendationSourceType: source?.sourceType ?? null,
      recommendationSourceUserId: null,
      recommendationSourceText: source?.displayName ?? null,
      sharedMealId: null,
      note: visitIndex % 4 === 0
        ? `${place.cuisine}体验${preferences.includes(place.cuisine) ? '很符合偏好' : '有明显个性'}。`
        : null,
      myActualSpend: amount.perPerson,
      createdAt: visitedAt, updatedAt: visitedAt, deletedAt: null,
    })
    records.push(visit)
    visits.push(visit.payload)

    if (visitIndex % 3 === 0) {
      const dishIndex = dishes.length + 1
      const dishID = `${prefix}_dish_${String(dishIndex).padStart(4, '0')}`
      const dish = recordOf('dish', dishID, {
        schemaVersion: 1, id: dishID, userId: ownerID, restaurantId: restaurant.id,
        visitId: visitID, name: `${place.cuisine}代表菜 · 虚构${String(dishIndex).padStart(3, '0')}`,
        taste: visitIndex % 2 === 0 ? '层次清楚' : '口味鲜明', rating,
        price: Math.max(12, Math.round(amount.perPerson * (0.25 + (visitIndex % 4) * 0.08))),
        photoId: null, sortOrder: 0, createdAt: visitedAt, updatedAt: visitedAt, deletedAt: null,
      })
      // Sync V1 creates the canonical legacy-compatible VisitDish association
      // atomically with the Dish. Sending a second association for the same
      // (user, visit, dish) tuple would violate the authoritative uniqueness
      // rule, so the seed manifest deliberately reuses that existing behavior.
      records.push(dish)
      dishes.push(dish.payload)
    }
  }

  const lists = []
  const listItems = []
  for (let listIndex = 0; listIndex < listCount; listIndex += 1) {
    const listID = `${prefix}_list_${String(listIndex + 1).padStart(2, '0')}`
    const timestamp = daysAgo(now, 180 - listIndex * 19)
    const visibility = ['public', 'friends', 'private'][listIndex % 3]
    const list = recordOf('restaurantList', listID, {
      schemaVersion: 1, id: listID, userId: ownerID,
      title: ['近期想再去', '城市散步餐桌', '朋友聚餐备选', '安静的一人食', '旅行味觉清单'][listIndex % 5],
      description: 'Development 虚拟食单，只包含合成餐厅。', visibility,
      isRanked: listIndex % 2 === 0, coverMode: 'automatic', customCoverPhotoId: null,
      createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
    })
    records.push(list)
    lists.push(list.payload)
    const candidates = rotate(visitedPlaces, listIndex * 7).slice(0, Math.min(7, visitedPlaces.length))
    candidates.forEach((place, itemIndex) => {
      const restaurant = restaurantByPlace.get(place.id)
      const itemID = `${prefix}_list_item_${String(listIndex + 1).padStart(2, '0')}_${String(itemIndex + 1).padStart(2, '0')}`
      const item = recordOf('restaurantListItem', itemID, {
        schemaVersion: 1, id: itemID, userId: ownerID, listId: listID,
        restaurantId: restaurant.id, restaurantGlobalKey: place.globalKey,
        position: itemIndex, note: itemIndex === 0 ? '这张虚拟清单的第一候选' : '',
        restaurant: {
          globalKey: place.globalKey, restaurantId: restaurant.id,
          placeIdentities: restaurant.placeIdentities.map(({ provider, externalId, isPrimary }) => ({
            provider, externalId, isPrimary,
          })),
          name: restaurant.name, address: restaurant.address, city: restaurant.city,
          latitude: restaurant.latitude, longitude: restaurant.longitude,
          markerPhotoId: null, merchantImageUrl: null, markerEmoji: restaurant.markerEmoji,
        },
        createdAt: timestamp, updatedAt: timestamp, deletedAt: null,
      })
      records.push(item)
      listItems.push(item.payload)
    })
  }

  return {
    ownerID, prefix, index, tier, similarityGroup, ratingPersona, spendPersona,
    city, preferences, visitedPlaceIDs: visitedPlaces.map((place) => place.id),
    wantedPlaceIDs: wantedPlaces.map((place) => place.id),
    records, profile: profileRecord?.payload ?? null,
    restaurants: [...restaurantByPlace.values()], visits, dishes, visitDishes,
    recommendationSources, companions, lists, listItems,
  }
}

function makeProfileRecord(ownerID, profile, now) {
  return recordOf('profile', ownerID, {
    schemaVersion: 1, userId: ownerID, displayName: profile.displayName,
    bio: profile.bio, city: profile.city, avatarPhotoId: null,
    avatarPresetId: profile.avatarPresetId, visibility: profile.visibility,
    createdAt: profile.createdAt, updatedAt: now.toISOString(), deletedAt: null,
  })
}

function makeRestaurantRecord(ownerID, entityID, place, status, timestamp, ratingPersona, spendPersona) {
  const baseRating = ratingPersona === 'generous' ? 4.5 : ratingPersona === 'strict' ? 3.5 : 4.0
  const rated = status === 'visited' && hash32(`${ownerID}:${place.id}:restaurant-rating`) % 4 !== 0
  const overallRating = rated ? clampHalf(baseRating + ((hash32(place.id + ownerID) % 3) - 1) * 0.5) : null
  return recordOf('restaurant', entityID, {
    schemaVersion: 1, id: entityID, userId: ownerID,
    placeIdentities: [{
      provider: 'manual', externalId: place.externalID, isPrimary: true,
      createdAt: timestamp, updatedAt: timestamp,
    }],
    name: place.name, address: place.address, city: place.city,
    latitude: place.latitude, longitude: place.longitude, status,
    preferenceLevel: overallRating !== null && overallRating >= 4.5 ? 'favorite' : 'normal',
    overallRating, foodRating: overallRating,
    environmentRating: overallRating === null ? null : clampHalf(overallRating - 0.5),
    serviceRating: overallRating, valueRating: overallRating,
    tags: [place.cuisine], longTermNote: '',
    pricePerPerson: spendFor(spendPersona, place.cuisine, `${ownerID}:${place.id}:restaurant-spend`).perPerson,
    phone: null, openingHours: null, markerType: 'emoji', markerPhotoId: null,
    merchantImageUrl: null, markerEmoji: emojiFor(place.cuisine),
    createdAt: timestamp, updatedAt: timestamp, deletedAt: null, isTestData: true,
  })
}

function buildRelationships(currentUserID, demoUsers, now) {
  const friendships = []
  const follows = []
  const seenFriends = new Set()
  const seenFollows = new Set()
  const addFriend = (left, right) => {
    if (left === right) return
    const pair = [left, right].sort()
    const key = pair.join('|')
    if (seenFriends.has(key)) return
    seenFriends.add(key)
    friendships.push({ requesterID: left, addresseeID: right, createdAt: daysAgo(now, hash32(key) % 180) })
  }
  const addFollow = (from, to) => {
    if (from === to) return
    const key = `${from}|${to}`
    if (seenFollows.has(key)) return
    seenFollows.add(key)
    follows.push({ followerID: from, followedUserID: to, createdAt: daysAgo(now, hash32(key) % 220) })
  }

  ;[1, 2, 5, 9, 12, 18, 24, 31, 34].forEach((index) => addFriend(currentUserID, demoUsers[index - 1].ownerID))
  ;[1, 2, 3, 5, 7, 9, 12, 14, 18, 21, 24, 27, 31, 37].forEach((index) =>
    addFollow(currentUserID, demoUsers[index - 1].ownerID))

  for (const user of demoUsers) {
    const friendTarget = user.tier === 'heavy' ? 7 : user.tier === 'normal' ? 5 : user.tier === 'light' ? 2 : user.index % 4
    const followTarget = user.tier === 'heavy' ? 10 : user.tier === 'normal' ? 7 : user.tier === 'light' ? 3 : user.index % 3
    for (let offset = 1; offset <= friendTarget; offset += 1) {
      addFriend(user.ownerID, demoUsers[(user.index - 1 + offset * 7) % demoUsers.length].ownerID)
    }
    for (let offset = 1; offset <= followTarget; offset += 1) {
      addFollow(user.ownerID, demoUsers[(user.index - 1 + offset * 11) % demoUsers.length].ownerID)
    }
  }
  // Keep the requested total graph size bounded while preserving every
  // current-user edge and each tier's deterministic neighbourhood.
  return {
    friendships: friendships.slice(0, 105),
    follows: follows.slice(0, 125),
  }
}

function summarizeDataset(places, currentUser, demoUsers, relationships, now) {
  const demoVisits = demoUsers.flatMap((user) => user.visits)
  const demoRestaurants = demoUsers.flatMap((user) => user.restaurants)
  const demoDishes = demoUsers.flatMap((user) => user.dishes)
  const demoLists = demoUsers.flatMap((user) => user.lists)
  const visibility = countBy(demoVisits, (visit) => visit.visibility)
  const active7 = activeGlobalKeys(demoUsers, now, 7)
  const active30 = activeGlobalKeys(demoUsers, now, 30)
  const overlapInputs = Object.fromEntries(['S', 'A', 'B', 'C', 'D', 'E'].map((group) => {
    const values = demoUsers.filter((user) => user.similarityGroup === group).map((user) => ({
      userID: user.ownerID,
      sharedRestaurantCount: intersectionSize(currentUser.visitedPlaceIDs, user.visitedPlaceIDs),
      currentRestaurantCount: currentUser.visitedPlaceIDs.length,
      candidateRestaurantCount: user.visitedPlaceIDs.length,
    }))
    return [group, values]
  }))
  return {
    demoUserCount: demoUsers.length,
    tiers: countBy(demoUsers, (user) => user.tier),
    similarityGroups: countBy(demoUsers, (user) => user.similarityGroup),
    restaurantUniverseCount: places.length,
    currentUser: {
      restaurantCount: currentUser.visitedPlaceIDs.length,
      visitCount: currentUser.visits.length,
      wantToGoCount: currentUser.wantedPlaceIDs.length,
      dishCount: currentUser.dishes.length,
      listCount: currentUser.lists.length,
      recommendationSourceCount: currentUser.recommendationSources.length,
      companionCount: currentUser.companions.length,
    },
    demo: {
      ownedRestaurantRecords: demoRestaurants.length,
      visitCount: demoVisits.length,
      wantToGoCount: demoUsers.reduce((sum, user) => sum + user.wantedPlaceIDs.length, 0),
      dishCount: demoDishes.length,
      listCount: demoLists.length,
      relationshipCount: relationships.friendships.length + relationships.follows.length,
      friendshipCount: relationships.friendships.length,
      followCount: relationships.follows.length,
      visibility,
      activeRestaurant7DayCount: active7.size,
      activeRestaurant30DayCount: active30.size,
    },
    overlapInputs,
  }
}

function visitTimestamp(now, place, userIndex, visitIndex) {
  const placeNumber = numericSuffix(place.id)
  if (place.trendCohort === 'strong7d' && userIndex <= 30 && (userIndex + placeNumber) % 3 !== 0) {
    return daysAgo(now, (userIndex + placeNumber) % 7, 8 + (visitIndex % 12))
  }
  if (place.trendCohort === 'medium7d' && (userIndex * 3 + placeNumber) % 7 === 0) {
    return daysAgo(now, 1 + ((userIndex + placeNumber) % 6), 8 + (visitIndex % 12))
  }
  if (place.trendCohort === 'stable30d' && (userIndex * 2 + placeNumber) % 5 === 0) {
    return daysAgo(now, 8 + ((userIndex + placeNumber) % 21), 8 + (visitIndex % 12))
  }
  if (place.trendCohort === 'historical') {
    return daysAgo(now, 120 + ((userIndex * 17 + visitIndex) % 500), 8 + (visitIndex % 12))
  }
  return daysAgo(now, 31 + ((hash32(`${userIndex}:${visitIndex}:${place.id}`)) % 690), 8 + (visitIndex % 12))
}

function visibilityFor(userIndex, tier, visitIndex) {
  const roll = hash32(`${userIndex}:visibility:${visitIndex}`) % 100
  if (userIndex === 1) return roll < 76 ? 'public' : roll < 92 ? 'friends' : 'private'
  if (userIndex === 18) return roll < 48 ? 'public' : roll < 82 ? 'friends' : 'private'
  if (userIndex === 35) return roll < 24 ? 'public' : roll < 52 ? 'friends' : 'private'
  if (tier === 'sparse') return roll < 45 ? 'public' : roll < 65 ? 'friends' : 'private'
  return roll < 55 ? 'public' : roll < 80 ? 'friends' : 'private'
}

function ratingFor(persona, preferred, key) {
  if (persona === 'sparse' && hash32(`${key}:nil`) % 100 < 68) return null
  const base = persona === 'generous' ? 4.45 : persona === 'strict' ? 3.4 : persona === 'sparse' ? 3.9 : 4.0
  const preference = preferred ? 0.35 : -0.25
  const jitter = ((hash32(key) % 5) - 2) * 0.25
  return clampHalf(base + preference + jitter)
}

function spendFor(persona, cuisine, key) {
  let ranges = persona === 'budget' ? [25, 95]
    : persona === 'premium' ? [260, 620]
      : persona === 'mid' ? [90, 250] : [45, 480]
  if (['面馆', '小吃', 'Bakery'].includes(cuisine)) ranges = [20, Math.min(120, ranges[1])]
  if (['咖啡', '甜品', 'Brunch'].includes(cuisine)) ranges = [35, Math.min(220, ranges[1])]
  const categoryFloor = ['Fine Dining', '西餐', 'Bistro'].includes(cuisine) ? 160 : ranges[0]
  const raw = ranges[0] + (hash32(key) % (ranges[1] - ranges[0] + 1))
  const perPerson = Math.max(categoryFloor, raw)
  return { perPerson }
}

function preferencesForGroup(group, index) {
  if (group === 'S') return ['日料', '咖啡', '江浙菜', 'Bistro']
  if (group === 'A') return ['日料', '咖啡', '江浙菜', index % 2 ? '西餐' : 'Brunch']
  if (group === 'B') return ['日料', '粤菜', '东南亚', index % 2 ? '咖啡' : '韩餐']
  if (group === 'C') return ['火锅', '烧烤', '川菜', '小吃', '面馆']
  if (group === 'D') return ['韩餐', 'Bar food', '烧烤', 'Fine Dining']
  return [CUISINES[index % CUISINES.length]]
}

function rankedPlaces(places, key, score) {
  return [...places].sort((left, right) => {
    const difference = score(right) - score(left)
    return difference || hash32(`${key}:${left.id}`) - hash32(`${key}:${right.id}`) || left.id.localeCompare(right.id)
  })
}

function activeGlobalKeys(users, now, days) {
  const threshold = now.getTime() - days * 86_400_000
  const placeByRestaurantID = new Map()
  users.forEach((user) => user.restaurants.forEach((restaurant) => {
    placeByRestaurantID.set(restaurant.id, restaurant.placeIdentities[0].externalId)
  }))
  const keys = new Set()
  users.forEach((user) => user.visits.forEach((visit) => {
    if (new Date(visit.visitedAt).getTime() >= threshold) keys.add(placeByRestaurantID.get(visit.restaurantId))
  }))
  return keys
}

function countBy(items, key) {
  return items.reduce((counts, item) => {
    const value = key(item)
    counts[value] = (counts[value] ?? 0) + 1
    return counts
  }, {})
}

function recordOf(entityType, entityID, payload) {
  return { entityType, entityID, payload }
}

function validCurrentUserID(value) {
  return typeof value === 'string' && /^[a-zA-Z0-9:_-]{1,80}$/.test(value) &&
    value !== ADMIN_USER_ID && !value.startsWith(USER_PREFIX)
}

function popularityWeight(popularity) {
  return popularity === 'high' ? 240 : popularity === 'medium' ? 100 : 0
}

function emojiFor(cuisine) {
  if (cuisine === '日料') return '🍣'
  if (cuisine === '咖啡') return '☕️'
  if (cuisine === '火锅') return '🍲'
  if (cuisine === '烧烤') return '🍢'
  if (cuisine === '甜品' || cuisine === 'Bakery') return '🍰'
  if (cuisine === '面馆') return '🍜'
  return '🍽️'
}

function rotate(items, offset) {
  if (!items.length) return []
  const normalized = offset % items.length
  return [...items.slice(normalized), ...items.slice(0, normalized)]
}

function intersectionSize(left, right) {
  const rightSet = new Set(right)
  return left.reduce((count, value) => count + Number(rightSet.has(value)), 0)
}

function numericSuffix(value) {
  return Number(value.match(/(\d+)$/)?.[1] ?? 0)
}

function daysAgo(now, days, hour = 12) {
  const value = new Date(now)
  value.setUTCDate(value.getUTCDate() - days)
  value.setUTCHours(hour, 0, 0, 0)
  return value.toISOString()
}

function clampHalf(value) {
  return Math.max(0.5, Math.min(5, Math.round(value * 2) / 2))
}

function shortHash(value) {
  return hash32(value).toString(16).padStart(8, '0')
}

function hash32(value) {
  let hash = 2166136261
  for (const character of String(value)) {
    hash ^= character.codePointAt(0)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}
