import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  // Isolated ephemeral browser storage; no user database, account or real photo is touched.
  const page = await browser.newPage({ viewport: { width: 430, height: 932 } })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridVisitEditorPage } = await import('/src/hybrid/app/HybridVisitEditorPage.tsx')
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { db } = await import('/src/db/appDb.ts')
    const { CURRENT_USER_ID } = await import('/src/db/social.ts')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    const canvas = document.createElement('canvas'); canvas.width = 2; canvas.height = 2
    canvas.getContext('2d').fillRect(0, 0, 2, 2)
    window.testPNG = canvas.toDataURL('image/png').split(',')[1]
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const base = fixture.restaurants[0]
    let sequence = 0
    window.probe = { saved: 0, requests: [] }
    window.setup = async (tier, count, editing = true) => {
      const user = { ...fixture.profile.user, id: CURRENT_USER_ID, membershipTier: tier }
      const restaurant = { ...base, id: 'quota-restaurant', userId: CURRENT_USER_ID, visits: [], deletedAt: null }
      const visit = { ...base.visits[0], id: `quota-visit-${++sequence}`, restaurantId: restaurant.id, userId: CURRENT_USER_ID,
        note: '历史笔记', photos: Array.from({ length: count }, (_, i) => `data:image/png;base64,${window.testPNG}#${i}`),
        photoIds: Array(count).fill(null), dishes: [], companions: [], deletedAt: null }
      await db.users.put(user); await db.restaurants.put(restaurant)
      if (editing) await db.visits.put(visit)
      const profile = async () => ({ user, restaurants: [{ ...restaurant, visits: (await db.visits.toArray()).filter(v => v.restaurantId === restaurant.id) }],
        visits: await db.visits.toArray(), followerCount: 0, followingCount: 0, restaurantImages: {} })
      const platform = new TasteMapBrowserAdapter({ profile })
      const save = platform.visit.save
      platform.visit.save = async request => { window.probe.requests.push(request); return save(request) }
      window.probe.platform = platform; window.probe.db = db
      root.render(React.createElement(HybridVisitEditorPage, { key: sequence, platform, membershipTier: tier,
        visitID: editing ? visit.id : undefined, restaurantID: editing ? undefined : restaurant.id,
        restaurants: [restaurant], visits: editing ? [visit] : [],
        onClose: () => {}, onSaved: id => { window.probe.saved++; window.probe.restaurantID = id } }))
    }
    await window.setup('free', 3)
  })
  const note = page.getByRole('textbox', { name: '到访笔记', exact: true })
  const count = page.locator('.visit-photo-picker header small')
  const saveEdit = () => page.getByRole('button', { name: '保存修改', exact: true }).click()
  await note.waitFor()
  assert.equal(await count.textContent(), '3 / 2 张')
  assert.equal(await page.locator('.visit-photo-picker figure').count(), 3)
  assert.equal(await page.locator('.visit-photo-picker input[type=file]').count(), 0)
  await note.fill('只修改笔记，旧三张不丢')
  await saveEdit()
  await page.waitForFunction(() => window.probe.saved === 1)
  assert.equal(await page.evaluate(async () => (await window.probe.db.visits.get(window.probe.requests.at(-1).visitID)).photos.length), 3)

  await page.evaluate(() => window.setup('free', 0, false))
  await page.getByRole('heading', { name: '记录一次到访', exact: true }).waitFor()
  const png = Buffer.from(await page.evaluate(() => window.testPNG), 'base64')
  const files = n => Array.from({ length: n }, (_, index) => ({ name: `test-${index}.png`, mimeType: 'image/png', buffer: png }))
  await page.locator('.visit-photo-picker input[type=file]').setInputFiles(files(3))
  await page.waitForFunction(() => document.querySelector('.visit-photo-picker header small')?.textContent === '2 / 2 张')
  assert.equal(await page.locator('.visit-photo-picker figure').count(), 2)
  await page.getByRole('button', { name: '保存到我的地图', exact: true }).click()
  await page.waitForFunction(() => window.probe.saved === 2)
  const bypass = await page.evaluate(async () => {
    const request = window.probe.requests.at(-1)
    const saved = (await window.probe.db.visits.toArray()).find(v => v.photos.length === 2)
    try {
      await window.probe.platform.visit.save({ ...request, visitID: saved.id,
        browserPhotoMaterial: { ...request.browserPhotoMaterial, photos: [...saved.photos, 'new-material'] } })
      return 'incorrectly accepted'
    } catch (error) { return error.message }
  })
  assert.match(bypass, /2 张/)

  await page.evaluate(() => window.setup('member', 0))
  await note.waitFor()
  await page.locator('.visit-photo-picker input[type=file]').setInputFiles(files(21))
  await page.waitForFunction(() => document.querySelector('.visit-photo-picker header small')?.textContent === '20 / 20 张')
  await saveEdit()
  await page.waitForFunction(() => window.probe.saved === 3)
  assert.equal(await page.evaluate(async () => (await window.probe.db.visits.get(window.probe.requests.at(-1).visitID)).photos.length), 20)

  await page.evaluate(() => window.setup('free', 20))
  await note.waitFor()
  await note.fill('会员到期仍保留全部二十张')
  await saveEdit()
  await page.waitForFunction(() => window.probe.saved === 4)
  assert.equal(await page.evaluate(async () => (await window.probe.db.visits.get(window.probe.requests.at(-1).visitID)).photos.length), 20)
  assert.deepEqual(errors, [])
  console.log('PASS actual HybridVisitEditorPage + BrowserAdapter + IndexedDB: Free selects/saves 2, third bypass rejected; Premium selects/saves 20; historical 3/20 unrelated edits preserve all photos; no Native photo capability invoked in Browser.')
} finally { await browser.close() }
