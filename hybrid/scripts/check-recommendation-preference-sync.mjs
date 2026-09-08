import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
// Intercept every API request. This probe never writes a real server/account.
const server = new Map(); let revision = 0; let pushes = 0
async function device() {
  const context = await browser.newContext()
  const session = { owner: 'preference-sync-probe', offline: false, lostAck: false }
  await context.route('**/api/**', async route => {
    const request = route.request(); const url = new URL(request.url())
    if (!url.pathname.startsWith('/api/v1/recommendation-preferences/')) return route.abort()
    if (session.offline) return route.abort()
    const owner = session.owner
    if (!server.has(owner)) server.set(owner, new Map())
    const events = server.get(owner)
    if (url.pathname.endsWith('/push')) {
      if (request.headers()['x-taste-map-preference-owner'] !== owner) return route.fulfill({ status: 409, json: { error: 'account_changed', code: 'account_changed' } })
      pushes++
      const receipts = request.postDataJSON().events.map(event => {
        if (!events.has(event.eventID)) events.set(event.eventID, { ...event, revision: ++revision, receivedAt: new Date().toISOString() })
        return { eventID: event.eventID, revision: events.get(event.eventID).revision }
      })
      if (session.lostAck) { session.lostAck = false; return route.abort() }
      return route.fulfill({ json: { apiVersion: 1, ownerID: owner, receipts } })
    }
    const after = url.searchParams.get('cursor') ? Number(Buffer.from(url.searchParams.get('cursor').slice(4), 'base64url').toString()) : 0
    const found = [...events.values()].filter(event => event.revision > after).slice(0, 100)
    return route.fulfill({ json: { apiVersion: 1, ownerID: owner, events: found, hasMore: false,
      cursor: `rp1.${Buffer.from(String(found.at(-1)?.revision ?? after)).toString('base64url')}` } })
  })
  const page = await context.newPage()
  await page.goto('http://127.0.0.1:4179')
  return { page, context, session }
}
async function mount(page) {
  await page.evaluate(async () => {
    const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
    const { BrowserRecommendationPreferenceSync } = await import('/src/services/browserRecommendationPreferenceSync.ts')
    const { browserRecommendationPreferenceStore } = await import('/src/db/recommendationPreferences.ts')
    const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
    const { db } = await import('/src/db/appDb.ts')
    const fixture = await loadTasteMapBrowserDebugFixture()
    const owner = 'preference-sync-probe'
    const profile = { ...fixture.profile, user: { ...fixture.profile.user, id: owner }, restaurants: [0, 1].map(index => ({
      ...fixture.profile.restaurants[0], id: `sync-place-${index}`, userId: owner, name: `肯德基(同步${index}店)`, placeIdentities: [],
    })) }
    const state = window.preferenceSyncProbe = { db, owner, profile, enabled: false }
    state.sync = new BrowserRecommendationPreferenceSync(browserRecommendationPreferenceStore, undefined, () => {}, () => state.enabled)
    state.adapter = new TasteMapBrowserAdapter({ profile: async () => profile }, state.sync)
    state.adapter.acceptProfileSnapshot(profile)
    await state.adapter.recommendations.preference()
  })
}
const sync = page => page.evaluate(async () => {
  const p = window.preferenceSyncProbe; p.enabled = true
  try { await p.sync.syncNow(); return { ok: true } } catch (error) { return { ok: false, message: error.message } }
  finally { p.enabled = false }
})
try {
  const a = await device(); const b = await device()
  await mount(a.page); await mount(b.page)
  await a.page.evaluate(async () => {
    const p = window.preferenceSyncProbe
    localStorage.setItem(`tastemap:recommendation-exclusions:v1:${p.owner}`, '["amap:old"]')
    await p.adapter.recommendations.preference('sync-place-0')
  })
  await b.page.evaluate(async () => { await window.preferenceSyncProbe.adapter.recommendations.preference('sync-place-1') })
  a.session.offline = true
  assert.equal((await sync(a.page)).ok, false)
  const beforeReload = await a.page.evaluate(async () => (await window.preferenceSyncProbe.db.recommendationPreferences.get(window.preferenceSyncProbe.owner)).entries.map(item => item.event.eventID))
  await a.page.reload(); await mount(a.page)
  assert.deepEqual(await a.page.evaluate(async () => (await window.preferenceSyncProbe.db.recommendationPreferences.get(window.preferenceSyncProbe.owner)).entries.map(item => item.event.eventID)), beforeReload, 'IndexedDB preserves exact pending event IDs across reload')
  assert.equal(await a.page.evaluate(() => localStorage.getItem(`tastemap:recommendation-exclusions:v1:${window.preferenceSyncProbe.owner}`)), '["amap:old"]', 'legacy key is retained')
  a.session.offline = false; a.session.lostAck = true
  assert.equal((await sync(a.page)).ok, false)
  assert.equal((await sync(a.page)).ok, true)
  assert.equal((await sync(b.page)).ok, true)
  assert.equal((await sync(a.page)).ok, true)
  for (const device of [a, b]) {
    const snapshot = await device.page.evaluate(() => window.preferenceSyncProbe.adapter.recommendations.preference())
    assert.deepEqual(snapshot.excludedIDs, ['amap:old', 'sync-place-0', 'sync-place-1'])
    assert.deepEqual(snapshot.intentFeedback.contextCounts, { everyday_fast_food: 2 })
    assert.equal(await device.page.evaluate(async () => (await window.preferenceSyncProbe.db.recommendationPreferences.get(window.preferenceSyncProbe.owner)).entries.filter(item => item.pending).length), 0)
  }
  const beforeSwitch = pushes
  b.session.owner = 'different-authenticated-owner'
  assert.equal((await sync(b.page)).ok, false)
  assert.equal(pushes, beforeSwitch, 'preflight owner mismatch never uploads private local state')
  assert.equal(server.get('different-authenticated-owner').size, 0)
  assert.equal(server.get('preference-sync-probe').size, 3, 'lost acknowledgement and legacy imports remain idempotent')
  console.log('PASS: actual Browser adapter + IndexedDB reload/outbox + intercepted authenticated HTTP + two-device union + legacy preservation + account mismatch')
} finally { await browser.close() }
