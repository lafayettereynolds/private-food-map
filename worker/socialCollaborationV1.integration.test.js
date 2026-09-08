import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it } from 'vitest'
import worker from './index'
import { applyAllMigrations } from './testSupport/migrations.js'

const now = () => new Date().toISOString()

describe('Social collaboration and Community interactions V1', () => {
  let database

  beforeEach(async () => {
    database = makeDatabase()
    for (const [id, name, visibility] of [
      ['tm_a', 'Alice', 'public'], ['tm_b', 'Bob', 'public'], ['tm_c', 'Carol', 'public'],
    ]) await seedUser(database, id, name, visibility)
    await acceptFriendship(database, 'tm_a', 'tm_b')
    await seedRestaurantVisit(database, 'tm_a', 'shared', 'friends')
    await seedRestaurantVisit(database, 'tm_b', 'public', 'public')
  })

  it('requires explicit accepted-friend consent to link and unlink a private Companion', async () => {
    await seedCompanion(database, 'tm_a', 'companion-a', 'Bob in my address book')
    const created = await jsonAPI(database, 'tm_a', '/api/v1/social/companion-links', 'POST', {
      companionId: 'companion-a', targetUserId: 'tm_b',
    })
    expect(created).toMatchObject({ companionId: 'companion-a', targetUserId: 'tm_b', status: 'pending' })
    expect(database.get("SELECT linked_user_id FROM dining_companions WHERE id = 'companion-a'").linked_user_id).toBeNull()

    expect((await api(database, 'tm_c', `/api/v1/social/companion-links/${created.id}`, 'POST', { action: 'accept' })).status).toBe(404)
    const accepted = await jsonAPI(database, 'tm_b', `/api/v1/social/companion-links/${created.id}`, 'POST', { action: 'accept' })
    expect(accepted.status).toBe('accepted')
    expect(database.get("SELECT linked_user_id FROM dining_companions WHERE id = 'companion-a'").linked_user_id).toBe('tm_b')
    expect(database.get("SELECT entity_type FROM sync_change_log_v6 WHERE mutation_id = ?", `social:companion:${created.id}:accept`).entity_type).toBe('companion')

    const unlinked = await jsonAPI(database, 'tm_b', `/api/v1/social/companion-links/${created.id}`, 'POST', { action: 'unlink' })
    expect(unlinked.status).toBe('unlinked')
    expect(database.get("SELECT linked_user_id FROM dining_companions WHERE id = 'companion-a'").linked_user_id).toBeNull()

    await seedCompanion(database, 'tm_a', 'companion-c', 'Carol')
    expect((await api(database, 'tm_a', '/api/v1/social/companion-links', 'POST', {
      companionId: 'companion-c', targetUserId: 'tm_c',
    })).status).toBe(403)
  })

  it('returns public friend suggestions without exposing auth identity fields', async () => {
    const suggestions = await jsonAPI(database, 'tm_c', '/api/v1/social/suggestions?limit=10')
    expect(suggestions.items.map((item) => item.user.profile.userId)).toEqual(
      expect.arrayContaining(['tm_a', 'tm_b']),
    )
    expect(JSON.stringify(suggestions)).not.toContain('appleSub')
    expect(JSON.stringify(suggestions)).not.toContain('email')
  })

  it('lists owner private directories, accepts mutual-follow links, and isolates private avatars', async () => {
    await seedCompanion(database,'tm_a','private-person','My friend')
    for(const [a,b] of [['tm_a','tm_c'],['tm_c','tm_a']]) await database.prepare(`INSERT INTO follows(id,follower_id,followed_user_id,created_at,updated_at,server_version) VALUES(?,?,?,?,?,1)`).bind(a+b,a,b,now(),now()).run()
    const page=await jsonAPI(database,'tm_a','/api/v1/directory')
    expect(page.entries).toEqual(expect.arrayContaining([expect.objectContaining({id:'private-person',kind:'companion'})]))
    expect(page.users.map(p=>p.id)).toContain('tm_c')
    const link=await jsonAPI(database,'tm_a','/api/v1/directory','POST',{kind:'companion',id:'private-person',action:'linkCompanion',targetUserID:'tm_c'})
    expect(link.status).toBe('pending')
    expect(database.get("SELECT linked_user_id FROM dining_companions WHERE id='private-person'").linked_user_id).toBeNull()
    await jsonAPI(database,'tm_c',`/api/v1/social/companion-links/${link.id}`,'POST',{action:'accept'})
    expect(database.get("SELECT linked_user_id FROM dining_companions WHERE id='private-person'").linked_user_id).toBe('tm_c')
    const avatar='data:image/jpeg;base64,'+Buffer.from([255,216,255,224,255,217]).toString('base64')
    await jsonAPI(database,'tm_a','/api/v1/directory','POST',{kind:'companion',id:'private-person',action:'avatar',avatarData:avatar})
    expect((await api(database,'tm_a','/api/v1/directory/avatar/companion/private-person')).headers.get('Cache-Control')).toBe('private, no-store')
    expect((await api(database,'tm_b','/api/v1/directory/avatar/companion/private-person')).status).toBe(403)
    expect((await api(database,'tm_b','/api/v1/directory','POST',{kind:'companion',id:'private-person',action:'avatar',avatarData:null})).status).toBe(403)
    expect(JSON.stringify(await jsonAPI(database,'tm_a','/api/v1/directory'))).not.toContain('base64')
  })

  it('links a recommendation source privately with sync log, unlinks without rewriting Visits',async()=>{
    await database.prepare(`INSERT INTO recommendation_sources(id,user_id,display_name,normalized_name,source_type,created_at,updated_at) VALUES('source-a','tm_a','Source','Source','friend',?,?)`).bind(now(),now()).run()
    const before=database.get("SELECT note FROM visits WHERE id='visit-tm_a-shared'")
    await jsonAPI(database,'tm_a','/api/v1/directory','POST',{kind:'source',id:'source-a',action:'linkSource',targetUserID:'tm_c'})
    expect(database.get("SELECT linked_user_id FROM recommendation_sources WHERE id='source-a'").linked_user_id).toBe('tm_c')
    expect(database.get("SELECT count(*) n FROM sync_change_log_v6 WHERE entity_id='source-a'").n).toBe(1)
    expect((await api(database,'tm_b','/api/v1/directory','POST',{kind:'source',id:'source-a',action:'linkSource',targetUserID:null})).status).toBe(403)
    await jsonAPI(database,'tm_a','/api/v1/directory','POST',{kind:'source',id:'source-a',action:'linkSource',targetUserID:null})
    expect(database.get("SELECT linked_user_id FROM recommendation_sources WHERE id='source-a'").linked_user_id).toBeNull()
    expect(database.get("SELECT note FROM visits WHERE id='visit-tm_a-shared'")).toEqual(before)
    expect(database.get("SELECT count(*) n FROM private_directory_audit WHERE entity_id='source-a'").n).toBe(2)
  })

  it('rejects self/private source attribution and invalid avatars, then removes private avatars', async () => {
    await database.prepare(`INSERT INTO recommendation_sources(id,user_id,display_name,normalized_name,source_type,created_at,updated_at) VALUES('source-private','tm_a','Source','Source','friend',?,?)`).bind(now(),now()).run()
    const change=(body)=>api(database,'tm_a','/api/v1/directory','POST',{kind:'source',id:'source-private',...body})
    expect((await change({action:'linkSource',targetUserID:'tm_a'})).status).toBe(403)
    await database.prepare("UPDATE user_profiles SET visibility='private' WHERE user_id='tm_c'").run()
    expect((await change({action:'linkSource',targetUserID:'tm_c'})).status).toBe(403)
    expect((await change({action:'avatar',avatarData:'data:image/svg+xml,<svg/>'})).status).toBe(403)
    expect((await change({action:'avatar',avatarData:'data:image/jpeg;base64,'+'A'.repeat(100_001)})).status).toBe(403)
    const avatar='data:image/jpeg;base64,'+Buffer.from([255,216,255,224,255,217]).toString('base64')
    expect((await change({action:'avatar',avatarData:avatar})).status).toBe(200)
    expect((await jsonAPI(database,'tm_a','/api/v1/directory')).entries[0].avatarURL).toContain('/avatar/source/source-private')
    expect((await jsonAPI(database,'tm_b','/api/v1/directory')).entries).toEqual([])
    expect((await change({action:'avatar',avatarData:null})).status).toBe(200)
    expect((await api(database,'tm_a','/api/v1/directory/avatar/source/source-private')).status).toBe(403)
    expect((await jsonAPI(database,'tm_a','/api/v1/directory')).entries[0].avatarURL).toBeNull()
    expect(database.get("SELECT count(*) n FROM private_directory_audit WHERE entity_id='source-private'").n).toBe(2)
  })

  it('does not let two accepted requests bind one private Companion to different users', async () => {
    await acceptFriendship(database, 'tm_a', 'tm_c')
    await seedCompanion(database, 'tm_a', 'companion-race', 'One private name')
    const requestB = await jsonAPI(database, 'tm_a', '/api/v1/social/companion-links', 'POST', {
      companionId: 'companion-race', targetUserId: 'tm_b',
    })
    const requestC = await jsonAPI(database, 'tm_a', '/api/v1/social/companion-links', 'POST', {
      companionId: 'companion-race', targetUserId: 'tm_c',
    })
    expect((await api(database, 'tm_b', `/api/v1/social/companion-links/${requestB.id}`, 'POST', {
      action: 'accept',
    })).status).toBe(200)
    expect((await api(database, 'tm_c', `/api/v1/social/companion-links/${requestC.id}`, 'POST', {
      action: 'accept',
    })).status).toBe(409)
    expect(database.get("SELECT linked_user_id FROM dining_companions WHERE id = 'companion-race'").linked_user_id)
      .toBe('tm_b')
  })

  it('creates idempotent Shared Meal invitations, lets only the receiver accept/attach, and revokes without deleting their Visit', async () => {
    const body = {
      sourceVisitId: 'visit-tm_a-shared', participantUserIds: ['tm_b'], mutationId: 'invite-a-b-1',
    }
    const [first, concurrentRetry] = await Promise.all([
      jsonAPI(database, 'tm_a', '/api/v1/social/shared-meals', 'POST', body),
      jsonAPI(database, 'tm_a', '/api/v1/social/shared-meals', 'POST', body),
    ])
    const duplicate = await jsonAPI(database, 'tm_a', '/api/v1/social/shared-meals', 'POST', body)
    expect(concurrentRetry.mealId).toBe(first.mealId)
    expect([first.duplicate, concurrentRetry.duplicate]).toContain(false)
    expect(duplicate).toMatchObject({ duplicate: true, mealId: first.mealId })
    expect(database.get('SELECT COUNT(*) AS count FROM shared_meals').count).toBe(1)
    const participant = first.invitations[0]
    expect((await api(database, 'tm_a', `/api/v1/social/shared-meals/participants/${participant.participantId}`, 'POST', { action: 'accept' })).status).toBe(404)

    const accepted = await jsonAPI(database, 'tm_b', `/api/v1/social/shared-meals/participants/${participant.participantId}`, 'POST', { action: 'accept' })
    expect(accepted.status).toBe('accepted')
    await seedReceiverVisit(database, first.mealId)
    const attached = await jsonAPI(database, 'tm_b', `/api/v1/social/shared-meals/participants/${participant.participantId}`, 'POST', {
      action: 'attach', visitId: 'visit-tm_b-receiver',
    })
    expect(attached.visitId).toBe('visit-tm_b-receiver')
    expect((await api(database, 'tm_a', `/api/v1/social/shared-meals/participants/${participant.participantId}`, 'POST', {
      action: 'attach', visitId: 'visit-tm_b-receiver',
    })).status).toBe(404)

    const revoked = await jsonAPI(database, 'tm_a', `/api/v1/social/shared-meals/${first.mealId}`, 'DELETE')
    expect(revoked.status).toBe('revoked')
    expect(database.get("SELECT deleted_at FROM visits WHERE id = 'visit-tm_b-receiver'").deleted_at).toBeNull()
    const inbox = await jsonAPI(database, 'tm_b', '/api/v1/social/shared-meals?scope=incoming')
    expect(inbox.items).toEqual([])
  })

  it('authorizes likes/comments from the authenticated viewer, paginates, tombstones own comments, and inherits content visibility', async () => {
    const visitID = 'visit-tm_b-public'
    const firstLike = await jsonAPI(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/like`, 'PUT')
    const duplicateLike = await jsonAPI(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/like`, 'PUT')
    expect(firstLike).toMatchObject({ likedByViewer: true, likeCount: 1, duplicate: false })
    expect(duplicateLike).toMatchObject({ likedByViewer: true, likeCount: 1, duplicate: true })

    const comments = []
    for (let index = 0; index < 3; index += 1) {
      comments.push(await jsonAPI(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/comments`, 'POST', { body: `comment ${index}` }))
    }
    const firstPage = await jsonAPI(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/comments?limit=2`)
    const secondPage = await jsonAPI(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/comments?limit=2&cursor=${encodeURIComponent(firstPage.nextCursor)}`)
    expect(new Set([...firstPage.items, ...secondPage.items].map((value) => value.id)).size).toBe(3)
    expect((await api(database, 'tm_b', `/api/v1/community/comments/${comments[0].comment.id}`, 'DELETE')).status).toBe(404)
    const deleted = await jsonAPI(database, 'tm_a', `/api/v1/community/comments/${comments[0].comment.id}`, 'DELETE')
    expect(deleted.comment.deletedAt).toBeTypeOf('string')

    await database.prepare("UPDATE visits SET visibility = 'private' WHERE id = ?").bind(visitID).run()
    expect((await api(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/like`, 'PUT')).status).toBe(404)
    expect((await api(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/comments`)).status).toBe(404)
    const ownDeleteAfterPrivate = await api(database, 'tm_a', `/api/v1/community/comments/${comments[1].comment.id}`, 'DELETE')
    expect(ownDeleteAfterPrivate.status).toBe(200)
  })

  it('returns real public-profile overview and never lets direct IDs bypass visibility', async () => {
    await seedRestaurant(database, 'tm_a', 'common', 'wantToGo')
    await seedRestaurant(database, 'tm_b', 'common', 'wantToGo')
    const overview = await jsonAPI(database, 'tm_a', '/api/v1/community/users/tm_b/overview')
    expect(overview).toMatchObject({ apiVersion: 1, targetUserId: 'tm_b', friendCount: 1 })
    expect(overview.commonWantToGoCount).toBe(1)
    expect(overview.representativeRestaurants[0].name).toBe('public')
    expect(overview.tasteSummary.topTags).toContain('面')

    await database.prepare("UPDATE user_profiles SET visibility = 'private' WHERE user_id = 'tm_b'").run()
    expect((await api(database, 'tm_c', '/api/v1/community/users/tm_b/overview')).status).toBe(404)
    expect((await api(database, 'tm_c', '/api/v1/community/content/visit/visit-tm_b-public/like', 'PUT')).status).toBe(404)
  })

  it('rate limits authenticated comment mutations with a dedicated server bucket', async () => {
    const visitID = 'visit-tm_b-public'
    for (let index = 0; index < 20; index += 1) {
      expect((await api(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/comments`, 'POST', {
        body: `rate limit comment ${index}`,
      })).status).toBe(200)
    }
    expect((await api(database, 'tm_a', `/api/v1/community/content/visit/${visitID}/comments`, 'POST', {
      body: 'one request too many',
    })).status).toBe(429)
  })
})

async function seedUser(database, id, name, visibility) {
  await api(database, id, '/api/v1/sync/pull?schemaVersion=1&cursor=0')
  await database.prepare('UPDATE user_profiles SET display_name = ?, city = ?, visibility = ? WHERE user_id = ?')
    .bind(name, '杭州', visibility, id).run()
}

async function acceptFriendship(database, first, second) {
  const pair = [first, second].sort()
  await database.prepare(`INSERT INTO friendships (
    id, requester_id, addressee_id, status, created_at, updated_at,
    pair_user_a, pair_user_b, server_version, deleted_at
  ) VALUES (?, ?, ?, 'accepted', ?, ?, ?, ?, 1, NULL)`)
    .bind(`friend-${pair.join('-')}`, first, second, now(), now(), pair[0], pair[1]).run()
}

async function seedCompanion(database, owner, id, name) {
  await database.prepare(`INSERT INTO dining_companions (
    id, owner_user_id, display_name, normalized_name, linked_user_id,
    created_at, updated_at, deleted_at, server_version, last_mutation_id
  ) VALUES (?, ?, ?, ?, NULL, ?, ?, NULL, 1, ?)`)
    .bind(id, owner, name, name, now(), now(), `seed:${id}`).run()
}

async function seedRestaurantVisit(database, user, slug, visibility) {
  const restaurantID = await seedRestaurant(database, user, slug, 'visited')
  await database.prepare(`INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, rating, party_size, note,
    created_at, updated_at, visibility, deleted_at, server_version
  ) VALUES (?, ?, ?, ?, 4.5, 2, 'real note', ?, ?, ?, NULL, 1)`)
    .bind(`visit-${user}-${slug}`, user, restaurantID, now(), now(), now(), visibility).run()
}

async function seedRestaurant(database, user, slug, status) {
  const id = `restaurant-${user}-${slug}`
  await database.prepare(`INSERT INTO restaurants (
    id, user_id, amap_poi_id, name, address, city, latitude, longitude, status,
    preference_level, marker_type, marker_emoji, tags_json, created_at, updated_at,
    deleted_at, server_version
  ) VALUES (?, ?, '', ?, ?, '杭州', 30.25, 120.16, ?, 'normal', 'emoji', '🍜', '["面"]', ?, ?, NULL, 1)`)
    .bind(id, user, slug, `${slug}路 1号`, status, now(), now()).run()
  await database.prepare(`INSERT INTO restaurant_place_identities (
    restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
  ) VALUES (?, ?, 'apple_maps', ?, 1, ?, ?)`)
    .bind(id, user, `apple-${slug}`, now(), now()).run()
  return id
}

async function seedReceiverVisit(database, mealID) {
  const restaurant = await seedRestaurant(database, 'tm_b', 'receiver', 'visited')
  await database.prepare(`INSERT INTO visits (
    id, user_id, restaurant_id, visited_at, party_size, note, shared_meal_id,
    created_at, updated_at, visibility, deleted_at, server_version
  ) VALUES ('visit-tm_b-receiver', 'tm_b', ?, ?, 2, '', ?, ?, ?, 'private', NULL, 1)`)
    .bind(restaurant, now(), mealID, now(), now()).run()
}

async function jsonAPI(database, viewer, path, method = 'GET', body) {
  const response = await api(database, viewer, path, method, body)
  const value = await response.json()
  if (!response.ok) throw new Error(`${response.status}: ${value.error}`)
  return value
}

function api(database, viewer, path, method = 'GET', body) {
  return worker.fetch(new Request(`https://development.example.test${path}`, {
    method,
    headers: { ...(viewer ? { 'X-Taste-Map-Test-User': viewer } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), {
    DB: database, ASSETS: { fetch: () => new Response('not used') },
    APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test',
  })
}

function makeDatabase() {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON;')
  applyAllMigrations(sqlite)
  return new SQLiteD1Database(sqlite)
}

class SQLiteD1Database {
  constructor(sqlite) { this.sqlite = sqlite }
  prepare(sql) { return new SQLiteD1Statement(this.sqlite, sql) }
  async batch(statements) {
    this.sqlite.exec('BEGIN IMMEDIATE')
    try { const results = statements.map((statement) => statement.batchSync()); this.sqlite.exec('COMMIT'); return results }
    catch (error) { this.sqlite.exec('ROLLBACK'); throw error }
  }
  get(sql, ...values) { return this.sqlite.prepare(sql).get(...values) }
}

class SQLiteD1Statement {
  constructor(sqlite, sql, values = []) { this.sqlite = sqlite; this.sql = sql; this.values = values }
  bind(...values) { return new SQLiteD1Statement(this.sqlite, this.sql, values) }
  async first() { return this.sqlite.prepare(this.sql).get(...this.values) ?? null }
  async all() { return { results: this.sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} } }
  async run() { return this.runSync() }
  batchSync() {
    if (/^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)) return { success: true, results: this.sqlite.prepare(this.sql).all(...this.values), meta: {} }
    return this.runSync()
  }
  runSync() {
    const result = this.sqlite.prepare(this.sql).run(...this.values)
    return { success: true, results: [], meta: { changes: Number(result.changes) } }
  }
}
