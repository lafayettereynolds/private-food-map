import { DatabaseSync } from 'node:sqlite'
import { beforeEach, describe, expect, it } from 'vitest'
import { handleDiscoveryV1 } from './discoveryV1'
import { handleCommunityV1 } from './communityV1'
import { calculateTasteSimilarities } from './tasteSimilarity'
import { applyAllMigrations } from './testSupport/migrations.js'

const now = Date.now()
const iso = (daysAgo = 0) => new Date(now - daysAgo * 86400000).toISOString()
let db
const discover = (mode = 'trending', query = 'city=杭州') => handleDiscoveryV1(new Request(`https://audit.test/api/v1/discovery/${mode}?${query}`), db, 'viewer')
const community = (query = 'scope=latest') => handleCommunityV1(new Request(`https://audit.test/api/v1/community/feed?${query}`), db, 'viewer')
const names = page => page.items.map(x => x.restaurant.name)
const run = (sql, ...values) => db.prepare(sql).bind(...values).run()

beforeEach(async () => {
  const sqlite = new DatabaseSync(':memory:')
  sqlite.exec('PRAGMA foreign_keys = ON')
  applyAllMigrations(sqlite)
  db = new D1(sqlite)
  for (const id of ['viewer', 'bob', 'carol', 'dan', 'sparse']) {
    await run('INSERT INTO users (id,nickname,created_at,updated_at) VALUES (?,?,?,?)', id,id,iso(30),iso(1))
    await run("INSERT INTO user_profiles (user_id,display_name,city,visibility,created_at,updated_at) VALUES (?,?,'杭州','public',?,?)", id,id,iso(30),iso(1))
  }
})

describe('Discovery and Community safety regression', () => {
  it('uses cross-city stable shared ratings but returns only visible current-city direct targets', async () => {
    for (const user of ['viewer', 'bob']) for (let i = 0; i < 5; i++) await visit(user, `cross-${i}`, { identity: `cross-${i}`, city: '上海', rating: 5 - i / 2 })
    await visit('bob', 'local-direct', { city: '杭州' })
    await visit('bob', 'remote-direct', { city: '上海' })
    await visit('carol', 'ordinary-public-high', { city: '杭州' })
    const page = await discover('similar-taste')
    expect(names(page)).toEqual(['local-direct'])
    expect(page.evidenceAvailability).toMatchObject({ personalRatedRestaurantCount: 5, personalEvidence: 'eligible', localDirectRestaurantCount: 1 })
    expect(page.items[0].tasteEvidence).toMatchObject({ sharedRestaurantCount: 5, evidenceState: 'forming', supporterCount: 1 })
    expect(page.items[0].similarity).toBeNull()
  })
  for (const change of ['private', 'deleted', 'test', 'blocked', 'revoked']) it(`does not establish cross-city similarity using ${change} evidence`, async () => {
    for (const user of ['viewer', 'bob']) for (let i = 0; i < 5; i++) await visit(user, `cross-${i}`, { identity: `cross-${i}`, city: '上海', rating: 5 - i / 2 })
    await visit('bob', 'local-direct')
    if (change === 'private') await run("UPDATE visits SET visibility='private' WHERE id='v-bob-cross-0'")
    if (change === 'deleted') await run("UPDATE visits SET deleted_at=? WHERE id='v-bob-cross-0'", iso())
    if (change === 'test') await run("UPDATE visits SET is_test_data=1 WHERE id='v-bob-cross-0'")
    if (change === 'blocked') await run("INSERT INTO user_blocks (id,blocker_user_id,blocked_user_id,created_at,updated_at) VALUES ('b','bob','viewer',?,?)", iso(),iso())
    if (change === 'revoked') {
      await run("UPDATE visits SET visibility='friends' WHERE user_id='bob' AND id LIKE '%cross%'")
      await run("INSERT INTO friendships (id,requester_id,addressee_id,status,created_at,updated_at,pair_user_a,pair_user_b,server_version) VALUES ('f','viewer','bob','accepted',?,?,'bob','viewer',1)",iso(),iso())
      expect(names(await discover('similar-taste'))).toEqual(['local-direct'])
      await run("UPDATE friendships SET status='removed' WHERE id='f'")
    }
    const page = await discover('similar-taste')
    expect(page.items).toEqual([])
    expect(page.evidenceAvailability).toMatchObject({ personalEvidence: 'eligible', localDirectRestaurantCount: 0 })
  })
  it('never matches common name/address/tag fingerprints as stable restaurant evidence', async () => {
    for (const user of ['viewer', 'bob']) for (let i = 0; i < 5; i++) await visit(user, `common-${i}`, { name: `同名餐厅${i}`, identity: `${user}-${i}`, rating: 5 - i / 2 })
    await visit('bob','target')
    expect((await discover('similar-taste')).items).toEqual([])
  })
  it('merges three qualified supporters into one card with equal-user mean and actual repeated-visit evidence', async () => {
    for (const user of ['viewer','bob','carol','dan']) for (let i=0;i<5;i++) await visit(user,`shared-${i}`,{identity:`shared-${i}`,rating:5-i/2})
    for (const [user,rating] of [['bob',5],['carol',4],['dan',3]]) await visit(user,'target',{identity:'target',name:'目标餐厅',rating})
    await run("INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,visibility,created_at,updated_at) VALUES ('repeat','bob','r-bob-target',?,1,'public',?,?)",iso(0),iso(),iso())
    const page=await discover('similar-taste')
    expect(page.items).toHaveLength(1)
    const card=page.items[0]
    expect(card.ratings.similarTaste).toEqual({value:3.33,sampleCount:3})
    expect(card.tasteEvidence.aggregation).toBe('equal_user_mean')
    expect(card.tasteEvidence.supporterCount).toBe(3)
    expect(new Set(card.tasteEvidence.records.map(record => record.user.userId))).toEqual(new Set(['bob','carol','dan']))
    expect(card.reasons[1].text).toContain('平均6.7分（每人代表评分的普通均分）')
    expect(card.reasons[2].text).toBe('支持这家店的同味用户中，有1位留下过再次到访记录。')
  })
  it('ranks stronger target judgement before larger peer history, with sufficient percent only at ten shared restaurants', async () => {
    for (const user of ['viewer','bob','carol']) for (let i=0;i<(user==='bob'?5:10);i++) await visit(user,`rank-shared-${i}`,{identity:`rank-shared-${i}`,rating:3+(i%5)/2,city:'上海'})
    await visit('bob','strong-target',{rating:5})
    await visit('carol','weaker-target',{rating:4})
    const page=await discover('similar-taste')
    expect(names(page)).toEqual(['strong-target','weaker-target'])
    expect(page.items[0].similarity).toBeNull()
    expect(page.items[1].similarity).toMatchObject({percent:100,sharedRestaurantCount:10,evidenceState:'sufficient'})
    expect(page.items[1].similarity.weightedSimilarity).toBeCloseTo(0.5)
  })
  for (const reverse of [false, true]) it(`Discovery and Community exclude content across ${reverse ? 'reverse' : 'forward'} blocks`, async () => {
    await visit('bob', 'blocked-pick')
    expect(names(await discover())).toContain('blocked-pick')
    expect(names(await community())).toContain('blocked-pick')
    const [blocker, blocked] = reverse ? ['bob','viewer'] : ['viewer','bob']
    await run('INSERT INTO user_blocks (id,blocker_user_id,blocked_user_id,created_at,updated_at) VALUES (?,?,?,?,?)','block',blocker,blocked,iso(),iso())
    const discovery = await discover()
    expect(names(discovery)).not.toContain('blocked-pick')
    expect(names(await community())).not.toContain('blocked-pick')
  })

  it('removes blocked authors from personalized candidates, all rating cohorts, and both want sources', async () => {
    for (const user of ['viewer', 'bob', 'carol']) {
      for (let i = 0; i < 5; i++) await visit(user, `history-${i}`, { identity: `history-${i}`, rating: 5 - i / 2 })
    }
    await visit('bob', 'blocked-recommendation')
    await visit('bob', 'mixed-bob', { name: 'mixed', identity: 'mixed', rating: 5 })
    await visit('carol', 'mixed-carol', { name: 'mixed', identity: 'mixed', rating: 4 })
    await run("INSERT INTO friendships (id,requester_id,addressee_id,status,created_at,updated_at,pair_user_a,pair_user_b,server_version) VALUES ('friend','viewer','bob','accepted',?,?,'bob','viewer',1)", iso(), iso())
    for (const source of ['legacy', 'restaurant']) {
      for (const user of ['bob', 'carol']) {
        const id = await restaurant(user, `${source}-${user}`, {
          name: source, identity: source, status: source === 'restaurant' ? 'wantToGo' : 'visited',
        })
        if (source === 'legacy') await run('INSERT INTO want_to_go (id,user_id,restaurant_id,created_at) VALUES (?,?,?,?)', `want-${user}`, user, id, iso(10))
      }
    }
    expect(names(await discover('for-you'))).toContain('blocked-recommendation')
    expect(names(await discover('similar-taste'))).toContain('blocked-recommendation')
    expect(names(await discover())).toEqual(expect.arrayContaining(['legacy', 'restaurant']))
    await run("INSERT INTO user_blocks (id,blocker_user_id,blocked_user_id,created_at,updated_at) VALUES ('block','bob','viewer',?,?)", iso(), iso())
    for (const mode of ['for-you', 'similar-taste', 'trending']) {
      const page = await discover(mode)
      expect(names(page)).not.toContain('blocked-recommendation')
      expect(page.items.every(item => item.sourceUser?.userId !== 'bob')).toBe(true)
      const mixed = page.items.find(item => item.restaurant.name === 'mixed')
      expect(mixed.ratings.community).toEqual({ value: 4, sampleCount: 1 })
      expect(mixed.ratings.friends).toEqual({ value: null, sampleCount: 0 })
      expect(mixed.ratings.similarTaste).toEqual({ value: null, sampleCount: 1 })
    }
    const afterBlock = names(await discover())
    expect(afterBlock).not.toContain('legacy')
    expect(afterBlock).not.toContain('restaurant')
  })

  it('same-taste aggregate excludes reverse judgement and fewer-than-five-shared authors', async () => {
    const signal = []
    for (const [user, ratings] of [['viewer',[5,4.5,4,3.5,3]],['bob',[4.5,4,3.5,3,2.5]],['carol',[0.5,1,1.5,2,2.5]],['sparse',[5,4.5]]]) {
      for (const [i, rating] of ratings.entries()) {
        await visit(user, `${user}-shared-${i}`, { rating, identity:`shared-${i}` })
        signal.push({ userId:user, poiId:`shared-${i}`, ratingOutOfTen:rating*2, tags:['日料'] })
      }
    }
    for (const [user,rating] of [['bob',5],['carol',1],['sparse',5]]) {
      await visit(user, `${user}-candidate`, { name:'same-candidate', identity:'candidate', rating })
      signal.push({userId:user,poiId:'candidate',ratingOutOfTen:rating*2,tags:['日料']})
    }
    const similarity = calculateTasteSimilarities(signal,'viewer')
    expect(similarity.find(x=>x.userId==='carol')?.similarity).toBeLessThan(0)
    expect(similarity.find(x=>x.userId==='sparse')).toBeUndefined()
    const page = await discover('similar-taste')
    const candidate = page.items.find(x=>x.restaurant.name==='same-candidate')
    expect(candidate.sourceUser.userId).toBe('bob')
    expect(candidate.similarity).toBeNull()
    expect(candidate.tasteEvidence.evidenceState).toBe('forming')
    expect(candidate.ratings.similarTaste).toEqual({ value:null, sampleCount:1 })
  })

  it('retains popular places after 900 raw visits by one person through the shipping reader', async () => {
    await visit('carol','popular-c',{name:'popular',identity:'popular',daysAgo:5})
    await visit('dan','popular-d',{name:'popular',identity:'popular',daysAgo:5})
    const repeatedRestaurant = await visit('bob','noise',{daysAgo:1})
    expect(names(await discover())[0]).toBe('popular')
    for (let i=1;i<900;i++) await run("INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,created_at,updated_at,visibility) VALUES (?,'bob',?,?,5,?,?,'public')",`noise-${i}`,repeatedRestaurant,iso(1),iso(1),iso(1))
    const page = await discover()
    expect(names(page)[0]).toBe('popular')
    expect(page.items.find(item => item.restaurant.name === 'popular').trend.uniqueVisitorCount).toBe(2)
    expect(page.items.find(item => item.restaurant.name === 'noise').trend.uniqueVisitorCount).toBe(1)
  })

  it('keeps older owner ratings after 600 recent unrated Visits instead of falling back to cold start', async () => {
    for (let index = 0; index < 5; index++) {
      await visit('viewer', `old-rated-${index}`, { rating: 5 - index / 2, daysAgo: 60 })
    }
    await visit('bob', 'personal-pick', { rating: 5 })
    const repeatedRestaurant = await visit('viewer', 'recent-unrated', { rating: null })
    for (let index = 1; index < 600; index++) {
      await run("INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,created_at,updated_at,visibility) VALUES (?,'viewer',?,?,NULL,?,?,'private')",
        `unrated-${index}`, repeatedRestaurant, iso(1), iso(1), iso(1))
    }
    const page = await discover('for-you')
    expect(page.personalizationConfidence).toBe('medium')
    const candidate = page.items.find(item => item.restaurant.name === 'personal-pick')
    expect(candidate.personalTastePercent).toBeGreaterThan(0)
    expect(candidate.reasons[0]).toMatchObject({ code: 'HIGH_CUISINE_MATCH', evidence: { sampleCount: 5 } })
    expect(candidate.reasons.map(reason => reason.code)).not.toContain('TASTE_TAG_MATCH')
    expect(page.items.flatMap(item => item.reasons.map(reason => reason.code))).not.toContain('COLD_START_TRENDING')
  })

  it('matches canonical and persisted provider city suffixes', async () => {
    await visit('bob','canonical')
    await visit('carol','provider-suffix',{city:'杭州市'})
    const normal = await discover('trending','city=杭州')
    const suffixed = await discover('trending','city=杭州市')
    expect(names(normal).sort()).toEqual(['canonical','provider-suffix'])
    expect(names(suffixed).sort()).toEqual(['canonical','provider-suffix'])
  })

  it('excludes future visits and future wants from trend', async () => {
    await visit('bob','future-visit',{daysAgo:-20})
    await restaurant('carol','future-want-c',{name:'future-want',identity:'future-want',status:'wantToGo',daysAgo:-20})
    await restaurant('dan','future-want-d',{name:'future-want',identity:'future-want',status:'wantToGo',daysAgo:-20})
    const page=await discover('trending','city=杭州&window=7')
    expect(names(page)).not.toContain('future-visit')
    expect(names(page)).not.toContain('future-want')
    expect(names(await community())).not.toContain('future-visit')
  })

  it('retains the approved 7-day visits plus 30-day wants rule', async () => {
    await visit('bob', 'week-visit', { daysAgo: 6 })
    await visit('bob', 'month-visit', { daysAgo: 20 })
    for (const user of ['carol', 'dan']) await restaurant(user, `month-want-${user}`, {
      name: 'month-want', identity: 'month-want', status: 'wantToGo', daysAgo: 20,
    })
    const week = await discover('trending', 'city=杭州&window=7')
    expect(names(week)).toContain('week-visit')
    expect(names(week)).not.toContain('month-visit')
    expect(week.items.find(item => item.restaurant.name === 'month-want').trend).toMatchObject({
      windowDays: 7, uniqueVisitorCount: 0, wantToGoCount: 2,
    })
    expect(names(await discover('trending', 'city=杭州&window=30'))).toContain('month-visit')
  })

  it('does not choose its fallback city from future or explicit-test history', async () => {
    await run("UPDATE user_profiles SET city='' WHERE user_id='viewer'")
    await visit('viewer', 'real-history', { city: '杭州', daysAgo: 2 })
    await visit('viewer', 'future-history', { city: '北京', daysAgo: -20 })
    const test = await visit('viewer', 'test-history', { city: '上海', daysAgo: 1 })
    await run('UPDATE restaurants SET is_test_data=1 WHERE id=?', test)
    await visit('bob', 'city-candidate')
    const page = await discover('trending', '')
    expect(page.city).toBe('杭州')
    expect(names(page)).toContain('city-candidate')
  })

  it('uses all public activity including the viewer, never friends-only profile signals', async () => {
    await visit('viewer', 'own-public')
    await visit('bob', 'friend-profile-public-visit')
    await run("UPDATE user_profiles SET visibility='friends' WHERE user_id='bob'")
    await run("INSERT INTO friendships (id,requester_id,addressee_id,status,created_at,updated_at,pair_user_a,pair_user_b,server_version) VALUES ('friend','viewer','bob','accepted',?,?,'bob','viewer',1)", iso(), iso())
    for (const user of ['viewer', 'carol']) await restaurant(user, `public-want-${user}`, {
      name: 'public-want', identity: 'public-want', status: 'wantToGo', daysAgo: 20,
    })
    const page = await discover()
    expect(page.items.find(item => item.restaurant.name === 'own-public').trend.uniqueVisitorCount).toBe(1)
    expect(names(page)).not.toContain('friend-profile-public-visit')
    expect(page.items.find(item => item.restaurant.name === 'public-want').trend.wantToGoCount).toBe(2)
    await run("UPDATE user_profiles SET visibility='private' WHERE user_id='viewer'")
    const privateViewer = await discover()
    expect(names(privateViewer)).not.toContain('own-public')
    expect(names(privateViewer)).not.toContain('public-want')
  })

  it('does not infer a follow relation from friendship', async () => {
    await visit('bob','friend-only')
    await run("INSERT INTO friendships (id,requester_id,addressee_id,status,created_at,updated_at,pair_user_a,pair_user_b,server_version) VALUES ('friend','viewer','bob','accepted',?,?,'bob','viewer',1)",iso(),iso())
    expect(db.sqlite.prepare('SELECT COUNT(*) n FROM follows').get().n).toBe(0)
    const page=await community('scope=following')
    expect(names(page)).not.toContain('friend-only')
  })

  it('excludes test Restaurants from Discovery and Community', async () => {
    const id=await visit('bob','explicit-test')
    await run('UPDATE restaurants SET is_test_data=1 WHERE id=?',id)
    expect(names(await discover())).not.toContain('explicit-test')
    expect(names(await community())).not.toContain('explicit-test')
    const want = await restaurant('bob', 'explicit-test-want', { status: 'wantToGo' })
    await run('UPDATE restaurants SET is_test_data=1 WHERE id=?', want)
    const profile = path => handleCommunityV1(new Request(`https://audit.test/api/v1/community/users/bob/${path}`), db, 'viewer')
    const content = await profile('content?section=visits')
    expect(content.items).toEqual([])
    expect(content.statistics).toEqual({ visibleRestaurantCount: 0, visibleVisitCount: 0, visibleWantToGoCount: 0 })
    expect((await profile('content?section=want_to_go')).items).toEqual([])
    const overview = await profile('overview')
    expect(overview.representativeRestaurants).toEqual([])
    expect(overview.footprints).toEqual([])
    expect(overview.tasteSummary.ratedVisitCount).toBe(0)
  })

  it('preserves continuous ranks, distinct items, and frozen ranking time across pages', async () => {
    for (let i=0;i<5;i++) await visit('bob',`page-${i}`,{daysAgo:1+i/10})
    const first=await discover('trending','city=杭州&limit=2')
    const second=await discover('trending',`city=杭州&limit=2&cursor=${encodeURIComponent(first.nextCursor)}`)
    expect(first.items.map(x=>x.rank)).toEqual([1,2])
    expect(second.items.map(x=>x.rank)).toEqual([3,4])
    expect(second.generatedAt).toBe(first.generatedAt)
    expect(new Set([...names(first),...names(second)]).size).toBe(4)
  })
})

async function restaurant(user,slug,{name=slug,identity=slug,status='visited',city='杭州',daysAgo=1}={}) {
  const id=`r-${user}-${slug}`
  await run("INSERT INTO restaurants (id,user_id,amap_poi_id,name,address,city,latitude,longitude,status,preference_level,marker_type,marker_emoji,tags_json,created_at,updated_at) VALUES (?,?,'',?,?,?,30.2,120.1,?,'normal','emoji','🍜','[\"日料\"]',?,?)",id,user,name,`${name}路`,city,status,iso(daysAgo),iso(daysAgo))
  await run("INSERT INTO restaurant_place_identities (restaurant_id,user_id,provider,external_id,is_primary,created_at,updated_at) VALUES (?,?,'apple_maps',?,1,?,?)",id,user,identity,iso(daysAgo),iso(daysAgo))
  return id
}
async function visit(user,slug,{rating=5,daysAgo=1,...options}={}) {
  const id=await restaurant(user,slug,{daysAgo,...options})
  await run("INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,note,created_at,updated_at,visibility) VALUES (?,?,?,?,?,'',?,?,'public')",`v-${user}-${slug}`,user,id,iso(daysAgo),rating,iso(daysAgo),iso(daysAgo))
  return id
}
class D1 {
  constructor(sqlite){this.sqlite=sqlite}
  prepare(sql){return new Statement(this.sqlite,sql)}
  async batch(statements){this.sqlite.exec('BEGIN IMMEDIATE');try{const results=statements.map(x=>x.batchSync());this.sqlite.exec('COMMIT');return results}catch(error){this.sqlite.exec('ROLLBACK');throw error}}
}
class Statement {
  constructor(sqlite,sql,values=[]){Object.assign(this,{sqlite,sql,values})}
  bind(...values){return new Statement(this.sqlite,this.sql,values)}
  async first(){return this.sqlite.prepare(this.sql).get(...this.values)??null}
  async all(){return {results:this.sqlite.prepare(this.sql).all(...this.values),success:true,meta:{}}}
  async run(){return this.runSync()}
  batchSync(){return /^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)?{results:this.sqlite.prepare(this.sql).all(...this.values),success:true,meta:{}}:this.runSync()}
  runSync(){const result=this.sqlite.prepare(this.sql).run(...this.values);return {success:true,results:[],meta:{changes:Number(result.changes)}}}
}
