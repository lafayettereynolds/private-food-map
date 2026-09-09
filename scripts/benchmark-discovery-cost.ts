import { writeFileSync } from 'node:fs'
import { discoveryCostFixture } from '../worker/testSupport/discoveryCostFixture.js'
import { handleDiscoveryV1 } from '../worker/discoveryV1'
import { handleCommunityV1 } from '../worker/communityV1'

const destination=process.argv[2]
if (!destination) throw new Error('Provide a local evidence directory; this benchmark never contacts remote D1.')
// All endpoints use the same deterministic ranking clock on both sides.
Date.now=()=>Date.parse('2026-09-09T00:00:00.000Z')
const db=discoveryCostFixture({optimizedIndexes:process.argv.includes('--optimized'),
  ...(process.argv.includes('--dense')?{outside:400,outsideCity:'杭州'}:{})})
const results=[]
for(const mode of ['for-you','similar-taste','trending','latest']) {
  db.queries.length=0
  const started=performance.now()
  const request=new Request(`https://fixture.invalid/api/v1/${mode==='latest'?'community/feed?scope=latest&':'discovery/'+mode+'?'}city=杭州&limit=20`)
  const page=mode==='latest'?await handleCommunityV1(request,db as never,'viewer'):await handleDiscoveryV1(request,db as never,'viewer')
  results.push({mode,latencyMs:performance.now()-started,sqlCount:db.queries.length,page,queries:[...db.queries]})
}
await db.save(`${destination}/fixture.sqlite`)
writeFileSync(`${destination}/benchmark.json`,JSON.stringify(results,null,2))
console.log(results.map(x=>({mode:x.mode,sqlCount:x.sqlCount,latencyMs:x.latencyMs})))
