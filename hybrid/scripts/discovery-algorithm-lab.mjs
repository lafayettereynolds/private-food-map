// Local-only algorithm laboratory. No deployment, credentials or remote DB.
import { createServer } from 'node:http'
import { DatabaseSync } from 'node:sqlite'
import { createServer as createViteServer } from 'vite'
import { applyAllMigrations } from '../../worker/testSupport/migrations.js'

const vite = await createViteServer({ server: { middlewareMode: true }, appType: 'custom' })
const { default: worker } = await vite.ssrLoadModule('/worker/index.ts')
const sqlite = new DatabaseSync(':memory:')
sqlite.exec('PRAGMA foreign_keys = ON')
applyAllMigrations(sqlite)
class Statement {
  constructor(sql, values = []) { this.sql = sql; this.values = values }
  bind(...values) { return new Statement(this.sql, values) }
  async first() { return sqlite.prepare(this.sql).get(...this.values) ?? null }
  async all() { return { results: sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} } }
  async run() { return this.sync() }
  sync() {
    if (/^\s*(SELECT|PRAGMA|WITH)\b/i.test(this.sql)) return { results: sqlite.prepare(this.sql).all(...this.values), success: true, meta: {} }
    const result = sqlite.prepare(this.sql).run(...this.values)
    return { results: [], success: true, meta: { changes: Number(result.changes) } }
  }
}
const DB = { prepare: sql => new Statement(sql), batch: async statements => {
  sqlite.exec('BEGIN IMMEDIATE')
  try { const results = statements.map(statement => statement.sync()); sqlite.exec('COMMIT'); return results }
  catch (error) { sqlite.exec('ROLLBACK'); throw error }
} }
const owner = 'tm_p3a_ui_fixture'
const env = { DB, APP_ENVIRONMENT: 'development', SYNC_AUTH_MODE: 'development-test', ASSETS: { fetch: () => new Response('', { status: 404 }) } }
async function request(path, user = owner) {
  return worker.fetch(new Request(`http://localhost${path}`, { headers: { 'X-Taste-Map-Test-User': user } }), env)
}
const date = days => new Date(Date.now() - days * 86400000).toISOString()
for (const [user, name] of [[owner, '算法体验账号'], ['tm_lab_same', '同味食客'], ['tm_lab_other', '咖啡爱好者']]) {
  await request('/api/v1/sync/pull?schemaVersion=1&cursor=0', user)
  sqlite.prepare("UPDATE user_profiles SET display_name=?, city='杭州', visibility='public' WHERE user_id=?").run(name, user)
}
async function meal(user, index, rating, city = '杭州', tags = ['日料', '正餐']) {
  const id = `lab-${user}-${index}`, now = date(0), visited = date(index % 20)
  sqlite.prepare(`INSERT INTO restaurants (id,user_id,name,address,city,latitude,longitude,status,preference_level,marker_type,marker_emoji,tags_json,created_at,updated_at,price_per_person,amap_poi_id)
    VALUES (?,?,?,?,?,?,?,'visited','normal','emoji','🍜',?,?,?,?,'')`).run(id,user,`体验餐厅 ${index}`,`测试街 ${index} 号`,city,30.27 + index / 10000,120.15,JSON.stringify(tags),now,now,40 + index * 10)
  sqlite.prepare(`INSERT INTO restaurant_place_identities (restaurant_id,user_id,provider,external_id,is_primary,created_at,updated_at) VALUES (?,?,'apple_maps',?,1,?,?)`).run(id,user,`lab-place-${index}`,now,now)
  sqlite.prepare(`INSERT INTO visits (id,user_id,restaurant_id,visited_at,rating,party_size,note,created_at,updated_at,visibility,total_price,party_size_optional)
    VALUES (?,?,?,?,?,2,?,?,?,'public',?,2)`).run(`visit-${id}`,user,id,visited,rating,'算法实验用到访记录',visited,now,(40 + index * 10) * 2)
}
for (let index = 0; index < 12; index++) {
  const rating = [3, 3.5, 4, 4.5, 5][index % 5]
  await meal(owner,index,rating)
  await meal('tm_lab_same',index,rating - .5)
  await meal('tm_lab_other',index,5.5 - rating)
}
for (let index = 12; index < 54; index++) await meal(index % 3 ? 'tm_lab_same' : 'tm_lab_other',index,index % 3 ? 4.5 : 4,index % 4 ? '杭州' : '上海',index % 3 ? ['日料','正餐'] : ['咖啡'])
// Mutation is deliberately bounded to the local synthetic owner's ratings.
createServer(async (incoming, outgoing) => {
  try {
    const url = new URL(incoming.url, 'http://127.0.0.1:4187')
    if (url.pathname === '/api/v1/recommendation-preferences/push' && incoming.method === 'POST') {
      const chunks = []; let size = 0
      for await (const chunk of incoming) { size += chunk.length; if (size > 131072) throw new Error('body_too_large'); chunks.push(chunk) }
      const response = await worker.fetch(new Request('http://localhost' + url.pathname, {method:'POST',headers:{'content-type':'application/json','X-Taste-Map-Test-User':owner,'X-Taste-Map-Preference-Owner':owner},body:Buffer.concat(chunks)}),env)
      outgoing.writeHead(response.status, {'content-type':'application/json'}); outgoing.end(await response.text()); return
    }
    if (url.pathname === '/lab/profile' && incoming.method === 'POST') {
      const reverse = url.searchParams.get('taste') === 'reverse'
      for (let index = 0; index < 12; index++) sqlite.prepare('UPDATE visits SET rating=?,updated_at=? WHERE id=?').run(reverse ? 5.5 - [3,3.5,4,4.5,5][index % 5] : [3,3.5,4,4.5,5][index % 5],date(0),`visit-lab-${owner}-${index}`)
      outgoing.writeHead(200, { 'content-type': 'application/json' }); outgoing.end(JSON.stringify({ changed: true, reverse })); return
    }
    if (incoming.method !== 'GET' || !/^\/api\/v1\/(discovery|community)\//.test(url.pathname)) { outgoing.writeHead(404); outgoing.end(); return }
    const response = await request(url.pathname + url.search)
    outgoing.writeHead(response.status, { 'content-type': 'application/json' }); outgoing.end(await response.text())
  } catch (error) { outgoing.writeHead(500); outgoing.end(JSON.stringify({ error: String(error) })) }
}).listen(4187, '127.0.0.1', () => console.log('Algorithm lab: http://127.0.0.1:4187 — isolated synthetic records; actual Worker queries'))
