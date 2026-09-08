import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'})
try{
  const page=await browser.newPage({viewport:{width:375,height:812}})
  const errors=[];page.on('pageerror',e=>errors.push(e.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async()=>{
    const React=(await import('/node_modules/.vite/deps/react.js')).default
    const {createRoot}=(await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const {TasteMapReferralPage}=await import('/src/components/TasteMapReferralPage.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    document.getElementById('root').style.display='none'
    window.calls=[]
    const platform={events:{subscribe:async()=>({remove(){}})},referrals:{dashboard:async()=>{throw Error('signed out')},prepareRegistration:code=>{window.calls.push(code);return new Promise(resolve=>{window.finishRegistration=resolve})}}}
    createRoot(document.body.appendChild(document.createElement('div'))).render(React.createElement(TasteMapReferralPage,{platform,onBack(){}}))
  })
  const input=page.getByRole('textbox',{name:'24 位邀请码'})
  const button=page.getByRole('button',{name:'使用此邀请码',exact:true})
  await input.waitFor()
  assert.equal(await button.isDisabled(),true)
  for(const width of [375,402]){
    await page.setViewportSize({width,height:812})
    for(const theme of ['light','dark']){
      await page.emulateMedia({colorScheme:theme})
      const a=await input.boundingBox(),b=await button.boundingBox()
      assert.ok(a.x>=0&&a.x+a.width<=width&&b.y>=a.y+a.height)
      assert.ok(b.height>=44)
      assert.ok(Number(await input.evaluate(e=>parseFloat(getComputedStyle(e).fontSize)))>=16)
      await page.screenshot({path:'/tmp/tastemap-referral-'+width+'-'+theme+'.png',fullPage:true})
    }
  }
  await input.fill('  0123456789abcdefghijklmn  ')
  await button.click()
  assert.equal(await input.isDisabled(),true)
  assert.equal(await page.getByRole('button',{name:'正在保存邀请码…'}).isDisabled(),true)
  assert.deepEqual(await page.evaluate(()=>window.calls),['0123456789abcdefghijklmn'])
  await page.evaluate(()=>window.finishRegistration())
  await page.getByText('邀请码已保存。请返回“我的”，使用 Apple 登录创建新账号。已有账号不参与新用户奖励。',{exact:true}).waitFor()
  assert.deepEqual(errors,[])
  console.log('PASS referral: 375/402 light/dark layout, input 16px, 44px action, empty/busy guard, trim and success')
}finally{await browser.close()}
