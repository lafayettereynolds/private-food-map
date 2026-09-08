// Local, ephemeral admin UI verification. Never deploy this fixture server.
import { createServer } from 'node:http'
import { DatabaseSync } from 'node:sqlite'
import { createServer as createViteServer } from 'vite'
import { applyAllMigrations } from '../worker/testSupport/migrations.js'

const vite = await createViteServer({ server: { middlewareMode: true }, appType: 'custom' })
const { default: worker } = await vite.ssrLoadModule('/worker/index.ts')
const { sha256 } = await vite.ssrLoadModule('/worker/authV1.ts')
const sqlite = new DatabaseSync(':memory:')
applyAllMigrations(sqlite)
const now = new Date().toISOString()
for (const id of ['gift-admin-smoke', 'gift-recipient-smoke', 'free-recipient-smoke']) {
  sqlite.prepare("INSERT INTO users (id,nickname,auth_provider,created_at,updated_at) VALUES (?,?,'apple',?,?)").run(id, '测试 '+id, now, now)
}
const token = 'tm_access_local_admin_smoke_not_a_real_account'
sqlite.prepare(`INSERT INTO auth_sessions (id,user_id,access_token_hash,access_expires_at,refresh_token_hash,refresh_expires_at,created_at,updated_at,last_used_at)
  VALUES ('smoke','gift-admin-smoke',?,'2099-01-01T00:00:00Z','unused','2099-01-01T00:00:00Z',?,?,?)`).run(await sha256(token),now,now,now)
function statement(sql, values=[]) { return {
  bind:(...v)=>statement(sql,v),first:async()=>sqlite.prepare(sql).get(...values)??null,
  all:async()=>({results:sqlite.prepare(sql).all(...values)}),
  run:async()=>({meta:{changes:Number(sqlite.prepare(sql).run(...values).changes)}}),
} }
const server=createServer(async(req,res)=>{
  try {
    const chunks=[];for await(const chunk of req) chunks.push(chunk)
    const body=Buffer.concat(chunks)
    const response=await worker.fetch(new Request('http://127.0.0.1:4197'+req.url,{method:req.method,headers:req.headers,...(body.length?{body}: {})}),
      {DB:{prepare:sql=>statement(sql)},APP_ENVIRONMENT:'production',MEMBERSHIP_ADMIN_USER_IDS:'gift-admin-smoke',ASSETS:{fetch:()=>new Response('not found',{status:404})}})
    res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()))
  }catch {res.writeHead(500);res.end('local fixture server error')}
})
server.listen(4197,'127.0.0.1',()=>console.log('Ephemeral Gift Admin smoke: http://127.0.0.1:4197/internal/premium'))
async function close(){server.close();sqlite.close();await vite.close();process.exit(0)}
process.on('SIGINT',close);process.on('SIGTERM',close)
