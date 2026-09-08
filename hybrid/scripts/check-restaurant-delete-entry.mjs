import assert from 'node:assert/strict'

// Isolated shared-UI harness: never runs a real delete or contacts Native storage.
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  for (const width of [375, 430]) for (const colorScheme of ['light', 'dark']) {
    const page = await browser.newPage({ viewport: { width, height: 932 }, colorScheme })
    const errors = []
    page.on('pageerror', error => errors.push(error.message))
    await page.goto(process.env.TASTEMAP_UI_TEST_URL ?? 'http://127.0.0.1:4179')
    await page.evaluate(async ({ notificationFirst }) => {
      const React = (await import('/node_modules/.vite/deps/react.js')).default
      const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
      const { HybridAppShell } = await import('/src/hybrid/app/HybridAppShell.tsx')
      const { TasteMapBrowserAdapter } = await import('/src/platform/TasteMapBrowserAdapter.ts')
      const { TasteMapNativeAdapter } = await import('/src/platform/TasteMapNativeAdapter.ts')
      const { loadTasteMapBrowserDebugFixture } = await import('/src/platform/TasteMapBrowserDebugFixture.ts')
      await import('/src/hybrid/app/hybridShell.css')
      const fixture = await loadTasteMapBrowserDebugFixture()
      const original = fixture.profile.restaurants[0]
      const restaurant = { ...original, id: 'owned-delete-target', name: '删除入口隔离测试', visits: [], visitCount: 0, status: 'visited' }
      const profile = { ...fixture.profile, restaurants: [restaurant], visits: [] }
      const adapter = new TasteMapBrowserAdapter({ profile: async () => profile })
      Object.defineProperty(adapter, 'kind', { value: 'native' })
      adapter.acceptProfileSnapshot(profile)
      adapter.content.snapshot = async () => ({ ...fixture.content, lists: [] })
      const listeners = new Set()
      adapter.events.subscribe = async listener => { listeners.add(listener); return { remove: async () => listeners.delete(listener) } }
      let owned = true
      let deleted = false
      let nativeSheetOpen = false
      window.deletedDetailReads = 0
      const emit = event => { for (const listener of listeners) listener({ version: 1, sequence: 1, ...event }) }
      adapter.restaurant.get = async () => {
        if (deleted) { window.deletedDetailReads++; throw new Error('The Restaurant is unavailable') }
        return { restaurant, image: fixture.profile.restaurantImages[original.id], editableVisitIDs: [], viewerState: 'visited', capabilities: {
        canDeleteRestaurant: owned, canEditRestaurant: owned, canRecordVisit: owned, canAddToWantToGo: false, canAddToRoulette: true,
        } }
      }
      window.deleteBridgeRequests = []
      const native = new TasteMapNativeAdapter({ Capacitor: { Plugins: { TasteMapNative: {
        invoke: async ({ request }) => {
          window.deleteBridgeRequests.push(request)
          if (request.method === 'navigation.openNative' && request.payload.route === 'restaurantDelete') {
            nativeSheetOpen = true
            // Real Coordinator.current publishes the presented Native route,
            // not a fabricated presentedNativeRoute field on the DTO.
            emit({ name: 'navigation.route', payload: { route: { surface: 'restaurantDelete', identifier: request.payload.identifier }, owner: 'native', canGoBack: true, sourceRequestID: request.requestId } })
            // A queued underlying-detail acknowledgement must not disarm the
            // pending deletion while its Native sheet is still presented.
            emit({ name: 'navigation.route', payload: { route: { surface: 'restaurant', identifier: 'provider:place' }, owner: 'hybrid', canGoBack: true, sourceRequestID: 'older-detail-request' } })
            const panel = document.body.appendChild(document.createElement('div'))
            panel.dataset.nativeDeleteMock = 'true'
            panel.style.cssText = 'position:fixed;inset:0;z-index:99999;background:white;display:flex;align-items:center;justify-content:center'
            for (const confirm of [false, true]) {
              const button = panel.appendChild(document.createElement('button'))
              button.textContent = confirm ? '确认删除餐厅（测试）' : '取消删除（测试）'
              button.onclick = () => {
                if (confirm) {
                  deleted = true
                  if (notificationFirst) emit({ name: 'data.changed', payload: { reason: 'restaurantDeleted' } })
                }
                setTimeout(() => {
                  nativeSheetOpen = false
                  panel.remove()
                  if (confirm) {
                    // Real Coordinator owns the sole successful pop. Root's
                    // dismissal binding sees no Native sheet and cannot Back.
                    const completed = { name: 'navigation.route', payload: { route: { surface: 'profile' }, owner: 'hybrid', canGoBack: true, completedAction: 'restaurantDelete' } }
                    emit(completed)
                    emit(completed) // Duplicate transport must never pop twice.
                    if (!notificationFirst) setTimeout(() => emit({ name: 'data.changed', payload: { reason: 'restaurantDeleted' } }), 20)
                  } else {
                    emit({ name: 'data.changed', payload: { reason: 'nativePresentationDismissed' } })
                    emit({ name: 'navigation.route', payload: { route: { surface: 'restaurant', identifier: 'provider:place' }, owner: 'hybrid', canGoBack: true } })
                  }
                }, 40)
              }
            }
          }
          if (request.method === 'navigation.back') {
            if (nativeSheetOpen) throw new Error('Back raced the still-presented Native confirmation')
            return { version: 1, requestId: request.requestId, result: { route: { surface: 'profile' }, canGoBack: false } }
          }
          return { version: 1, requestId: request.requestId, result: request.method === 'runtime.info' ? { bridgeVersion: 1, supportedCapabilities: { nativeNavigation: true } } : {} }
        },
      } } } })
      adapter.navigation.openNative = native.navigation.openNative
      adapter.navigation.back = native.navigation.back
      document.getElementById('root').remove()
      window.history.replaceState(null, '', '#/profile')
      window.history.pushState(null, '', '#/restaurant/provider%3Aplace')
      const root = createRoot(document.body.appendChild(document.createElement('div')))
      root.render(React.createElement(HybridAppShell, { platform: adapter }))
      window.setDeletePermission = value => {
        owned = value
        for (const listener of listeners) listener({ version: 1, sequence: 1, name: 'data.changed', payload: { reason: 'permissionChanged' } })
      }
    }, { notificationFirst: colorScheme === 'light' })
    const deletion = page.getByRole('button', { name: '删除餐厅', exact: true })
    await deletion.waitFor()
    assert.equal(await deletion.count(), 1)
    assert.equal(await deletion.innerText(), '')
    assert.equal(await page.getByRole('button', { name: '删除这次到访', exact: true }).count(), 0)
    const edit = page.getByRole('button', { name: '修改餐厅头像', exact: true })
    assert.equal(await edit.count(), 1)
    const before = await page.evaluate(() => window.deleteBridgeRequests.length)
    assert.equal(before, 0)
    const geometry = await deletion.evaluate(button => {
      const a = button.getBoundingClientRect()
      const b = document.querySelector('.restaurant-avatar-edit-button').getBoundingClientRect()
      const c = document.querySelector('.tm-not-interested.is-image-overlay')?.getBoundingClientRect()
      const overlaps = r => r && a.left < r.right && a.right > r.left && a.top < r.bottom && a.bottom > r.top
      return { width: a.width, height: a.height, glyph: button.querySelector('svg').getBoundingClientRect().width, editOverlap: Boolean(overlaps(b)), exclusionOverlap: Boolean(overlaps(c)) }
    })
    assert.ok(geometry.width >= 43.99 && geometry.height >= 43.99, JSON.stringify(geometry))
    assert.equal(geometry.glyph, 17)
    assert.equal(geometry.editOverlap, false)
    assert.equal(geometry.exclusionOverlap, false)
    await deletion.click()
    await page.waitForFunction(() => window.deleteBridgeRequests.some(request => request.method === 'navigation.openNative'))
    const requests = await page.evaluate(() => window.deleteBridgeRequests.filter(request => request.method !== 'runtime.info'))
    assert.equal(requests.length, 1)
    assert.equal(requests[0].method, 'navigation.openNative')
    assert.deepEqual(requests[0].payload, { route: 'restaurantDelete', identifier: 'owned-delete-target' })
    await page.getByRole('button', { name: '取消删除（测试）', exact: true }).click()
    await page.locator('[data-native-delete-mock]').waitFor({ state: 'detached' })
    assert.equal(await page.evaluate(() => location.hash), '#/restaurant/provider%3Aplace')
    assert.equal(await page.evaluate(() => window.deleteBridgeRequests.filter(r => r.method === 'navigation.back').length), 0)
    await page.screenshot({ path: `/tmp/tastemap-delete-entry-${width}-${colorScheme}.png` })
    await page.evaluate(() => window.setDeletePermission(false))
    await deletion.waitFor({ state: 'detached' })
    assert.equal(await page.getByRole('button', { name: '删除餐厅', exact: true }).count(), 0)
    await page.evaluate(() => window.setDeletePermission(true))
    await deletion.click()
    await page.getByRole('button', { name: '确认删除餐厅（测试）', exact: true }).click()
    await page.waitForFunction(() => location.hash === '#/profile', undefined, { timeout: 3000 })
    await page.locator('.tm-hybrid-detail').waitFor({ state: 'detached' })
    assert.equal(await page.evaluate(() => window.deletedDetailReads), 0)
    await page.waitForTimeout(80)
    assert.equal(await page.evaluate(() => window.deleteBridgeRequests.filter(r => r.method === 'navigation.back').length), 0)
    assert.equal(await page.evaluate(() => window.deletedDetailReads), 0)
    assert.equal(await page.getByText('无法读取餐厅详情', { exact: true }).count(), 0)
    assert.deepEqual(errors, [])
    console.log(`PASS ${width}/${colorScheme}: real open + queued Detail echo; cancel stays; Native completion replaces Profile with zero JS Back/zero deleted-detail reads; generic notification ${colorScheme === 'light' ? 'before' : 'after'} completion; duplicate-safe; permission and geometry intact.`)
    await page.close()
  }
} finally { await browser.close() }
