import { DatabaseSync, backup } from 'node:sqlite'
import { readFileSync } from 'node:fs'
import { migrationFiles } from './migrations.js'

export function discoveryCostFixture({ optimizedIndexes = false, outside = 4000, outsideCity = '北京' } = {}) {
  const sqlite = new DatabaseSync(':memory:')
  for (const file of migrationFiles()) {
    if (!optimizedIndexes && file === '0041_discovery_candidate_indexes.sql') continue
    sqlite.exec(readFileSync(`migrations/${file}`, 'utf8'))
  }
  const at = '2026-09-08T12:00:00.000Z'
  for (const id of ['viewer','peer','outside']) {
    sqlite.prepare('INSERT INTO users(id,nickname,created_at,updated_at) VALUES(?,?,?,?)').run(id,id,at,at)
    sqlite.prepare("INSERT INTO user_profiles(user_id,display_name,city,visibility,created_at,updated_at) VALUES(?,?,'杭州','public',?,?)").run(id,id,at,at)
  }
  const restaurant=sqlite.prepare(`INSERT INTO restaurants(id,user_id,amap_poi_id,name,address,city,latitude,longitude,status,preference_level,marker_type,marker_emoji,tags_json,created_at,updated_at)
    VALUES(?,?,'',?,'fixture address',?,30,120,?,'normal','emoji','','["日料"]',?,?)`)
  const visit=sqlite.prepare(`INSERT INTO visits(id,user_id,restaurant_id,visited_at,rating,party_size,note,created_at,updated_at,visibility)
    VALUES(?,?,?,?,?,1,'',?,?,'public')`)
  const identity=sqlite.prepare("INSERT INTO restaurant_place_identities(restaurant_id,user_id,provider,external_id,is_primary,created_at,updated_at) VALUES(?,?,'apple_maps',?,1,?,?)")
  sqlite.exec('BEGIN')
  for(let i=0;i<outside+40;i++) {
    const user=i<10?'viewer':i<40?'peer':'outside'
    const id=`r${i}`;const city=i<40?(i%2?' 杭州 ':'杭州市'):outsideCity
    restaurant.run(id,user,id,city,i%4?'visited':'wantToGo',at,at)
    identity.run(id,user,`apple-${i>=10 && i<20 ? i-10 : i}`,at,at)
    for(let j=0;j<5;j++)visit.run(`v${i}-${j}`,user,id,at,3+(i%10)*0.2+(j%2)*0.1,at,at)
  }
  sqlite.exec('COMMIT')
  const queries=[]
  function statement(sql,values=[]) {
    const execute=()=>{
      const started=performance.now()
      const read=/^\s*(SELECT|WITH|PRAGMA)/i.test(sql)
      const result=read?sqlite.prepare(sql).all(...values):sqlite.prepare(sql).run(...values)
      queries.push({sql,values,milliseconds:performance.now()-started,returned:read?result.length:0,
        plan:read?sqlite.prepare('EXPLAIN QUERY PLAN '+sql).all(...values):[]})
      return {success:true,results:read?result:[],meta:{changes:read?0:Number(result.changes)}}
    }
    return {bind:(...v)=>statement(sql,v),all:async()=>execute(),first:async()=>execute().results[0]??null,run:async()=>execute()}
  }
  return {sqlite,queries,prepare:statement,batch:async s=>Promise.all(s.map(x=>x.all())),
    save:path=>backup(sqlite,path)}
}
