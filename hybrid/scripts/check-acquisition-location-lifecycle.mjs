import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { flushSync } = (await import('/node_modules/.vite/deps/react-dom.js')).default
    const { HybridAddRestaurantPage } = await import('/src/hybrid/app/HybridAddRestaurantPage.tsx')
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const probe = window.locationProbe = { requests: [], removed: 0 }
    const platform = {
      acquisition: {
        nearby: () => new Promise(resolve => probe.requests.push(resolve)),
        shared: async () => ({ candidates: [] }),
      },
      events: { subscribe: handler => {
        probe.emit = handler
        return new Promise(resolve => { probe.finishSubscription = () => resolve({ remove: async () => { probe.removed++ } }) })
      } },
    }
    probe.reply = (index, name, detectedCity) => probe.requests[index]({
      candidates: [{ id: name, name, city: detectedCity, address: '仅测试用候选', distanceMeters: 20,
        duplicateKind: 'none', image: { kind: 'foodDiningFallback', stableSeed: name, accessibilityLabel: name } }],
      detectedCity, location: null, message: null,
    })
    probe.unmount = () => flushSync(() => root.unmount())
    flushSync(() => root.render(React.createElement(HybridAddRestaurantPage, { platform, onOpenRestaurant: () => {}, onBack: () => {} })))
  })
  await page.waitForFunction(() => window.locationProbe.requests.length === 1)
  await page.getByRole('textbox', { name: '城市', exact: true }).fill('上海')
  await page.evaluate(() => window.locationProbe.emit({ name: 'app.lifecycle', payload: { state: 'resume' } }))
  await page.waitForFunction(() => window.locationProbe.requests.length === 2)
  await page.evaluate(() => window.locationProbe.reply(1, '当前请求测试餐厅', '杭州市'))
  await page.getByText('当前请求测试餐厅', { exact: true }).waitFor()
  assert.equal(await page.getByRole('textbox', { name: '城市', exact: true }).inputValue(), '上海')
  await page.evaluate(async () => {
    window.locationProbe.reply(0, '已过期请求测试餐厅', '北京市')
    await new Promise(resolve => requestAnimationFrame(resolve))
  })
  assert.equal(await page.getByText('已过期请求测试餐厅', { exact: true }).count(), 0)
  await page.evaluate(async () => {
    const probe = window.locationProbe
    probe.unmount()
    probe.finishSubscription()
    await Promise.resolve()
    probe.emit({ name: 'app.lifecycle', payload: { state: 'resume' } })
    probe.emit({ name: 'shareExtension.received', payload: {} })
  })
  assert.deepEqual(await page.evaluate(() => ({ requests: window.locationProbe.requests.length, removed: window.locationProbe.removed })), { requests: 2, removed: 1 })
  assert.deepEqual(errors, [])
  console.log('PASS actual acquisition lifecycle: current request wins, manual city preserved, late subscription removed, no hidden-page GPS restart')
} finally { await browser.close() }
