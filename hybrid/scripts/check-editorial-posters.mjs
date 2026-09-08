import assert from 'node:assert/strict'
import { mkdir, writeFile } from 'node:fs/promises'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
const output = process.env.TASTEMAP_POSTER_OUTPUT ?? '/tmp/tastemap-editorial-posters'
await mkdir(output, { recursive: true })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 }, timezoneId: 'Asia/Shanghai' })
  const errors = []; page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { MemoryPoster } = await import('/src/components/MemoryPoster.tsx')
    const { buildAnalyticsReport } = await import('/src/services/analyticsReport.ts')
    const { analyticsMemoryShareData } = await import('/src/services/analyticsMemoryShare.ts')
    const { buildDayEditorial } = await import('/src/services/analysisEditorialData.ts')
    const { buildOnThisDayShareData } = await import('/src/services/analysisShare.ts')
    const { exactMemoryReview } = await import('/src/services/onThisDayMemory.ts')
    const { renderAnalysisPosterBlob, renderAnalysisPosterSvg, prepareAnalysisPoster } = await import('/src/services/analysisPosterRenderer.ts')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/styles/global.css'); await import('/src/hybrid/app/hybridShell.css')
    const owner = fixture.profile.user.id, now = new Date('2026-09-07T12:00:00+08:00')
    const cuisines = ['日料', '火锅', '西餐', '咖啡', '面条', '中餐']
    const names = ['山野寿司', '一口热锅', '街角西餐', '午后咖啡', '巷子面馆', '小院家常菜']
    const restaurants = Array.from({ length: 36 }, (_, i) => ({ ...fixture.restaurants[0], id: `r${i}`, userId: owner, name: `${names[i % 6]} ${i+1}`, city: ['杭州','上海','成都'][i%3], tags: [cuisines[i%6]], deletedAt: null, visits: [] }))
    const visits = Array.from({ length: 252 }, (_, i) => ({ ...fixture.restaurants[0].visits[0], id: `v${i}`, userId: owner, restaurantId: `r${i%36}`, visitedAt: i<72 ? `${i<36?2024:2025}-09-07T19:00:00+08:00` : `2026-${String([1,3,5,7,8][Math.floor((i-72)/36)]).padStart(2,'0')}-${String(i%27+1).padStart(2,'0')}T${['08','12','15','19','23'][i%5]}:00:00+08:00`, visibility: i%11?'public':'private', deletedAt: null, rating: i%36<18?4.5:2.5, companions:['私密同行小林'], companionIds:['c1'], diningOccasions:['friends'], partySize:2, paymentMode:'aa', totalPrice:200, myActualSpend:100, photos:[],photoIds:[],dishes:[],note:'私密备注不可外发' }))
    const entry = (id,name) => ({id,displayName:name,identifiers:[id],ownerUserID:owner,updatedAt:'2026-09-01',deletedAt:null})
    const profile={...fixture.profile,restaurants,visits,restaurantImages:{},analyticsIdentity:{ownerUserID:owner,recordOwnerID:owner,companions:[entry('c1','私密同行小林')],sources:[{...entry('s1','具名可靠来源'),sourceType:'friend'},{...entry('s2','具名踩坑来源'),sourceType:'blogger'}],visitSourceLinks:visits.map(v=>({visitID:v.id,sourceID:Number(v.restaurantId.slice(1))<18?'s1':'s2'}))}}
    window.posterCases={}
    for(const mode of ['monthly','annual','source','companion']) {
      const args={mode,year:2026,month:8,now,companionID:mode==='companion'?'c1':undefined}
      window.posterCases[mode]={owner:analyticsMemoryShareData(buildAnalyticsReport(profile,args),profile,'owner'),share:analyticsMemoryShareData(buildAnalyticsReport(profile,{...args,excludePrivate:true}),profile)}
    }
    const day=visits.filter(v=>v.visitedAt.startsWith('2024')||v.visitedAt.startsWith('2025'))
    const daySafe=day.filter(v=>v.visibility==='public').map(v=>({...v,note:'',companions:[]}))
    window.posterCases.day={owner:buildDayEditorial(buildOnThisDayShareData(profile.user,exactMemoryReview(restaurants,day,now)),profile,restaurants,day,'owner',now),share:buildDayEditorial(buildOnThisDayShareData(profile.user,exactMemoryReview(restaurants,daySafe,now)),profile,restaurants,daySafe,'share',now)}
    window.renderCase=async(mode,audience)=>{const data=window.posterCases[mode][audience],before=JSON.stringify(data);const prepared=await prepareAnalysisPoster(data);const svg=renderAnalysisPosterSvg(prepared);const blob=await renderAnalysisPosterBlob(data);const encoded=await new Promise(resolve=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.readAsDataURL(blob)});return{encoded,svg,unmutated:before===JSON.stringify(data)}}
    document.body.innerHTML='<div id="poster-root"></div>';window.shares=[]
    const root=createRoot(document.getElementById('poster-root'))
    window.mountPoster=mode=>root.render(React.createElement(MemoryPoster,{key:mode,ownerData:window.posterCases[mode].owner,data:window.posterCases[mode].share,pageID:mode,platform:{kind:'native',share:{open:async payload=>window.shares.push(payload)}}}))
  })
  for(const mode of ['monthly','annual','source','companion','day']){
    for(const audience of ['owner','share']){
      const result=await page.evaluate(([mode,audience])=>window.renderCase(mode,audience),[mode,audience])
      assert.equal(result.unmutated,true)
      assert.match(result.svg,/viewBox="0 0 1080 1530"/)
      if(audience==='share')assert.doesNotMatch(result.svg,/私密同行小林|私密备注不可外发|具名可靠来源|具名踩坑来源/)
      if(mode==='source'&&audience==='owner')assert.match(result.svg,/具名踩坑来源/)
      await writeFile(`${output}/${mode}-${audience}.png`,Buffer.from(result.encoded.split(',')[1],'base64'))
    }
    await page.evaluate(mode=>window.mountPoster(mode),mode)
    const image=page.locator('.tm-hybrid-poster-preview img');await image.waitFor({timeout:60000})
    await page.getByRole('button',{name:'预览分享版',exact:true}).click()
    assert.equal(await page.evaluate(()=>window.shares.length),0)
    await image.waitFor({timeout:60000})
    const expected=await image.evaluate(async img=>{const blob=await(await fetch(img.src)).blob();return await new Promise(resolve=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.readAsDataURL(blob)})})
    await page.getByRole('button',{name:'系统分享',exact:true}).click()
    await page.waitForFunction(()=>window.shares.length===1)
    assert.equal(await page.evaluate(()=>window.shares[0].imageDataURL),expected)
    await page.evaluate(()=>{window.shares=[]})
  }
  assert.deepEqual(errors,[])
  console.log('PASS: five editorial layouts, ten owner/share PNGs, anonymous export, first action preview-only, exact shared PNG, immutable rendering')
}finally{await browser.close()}
