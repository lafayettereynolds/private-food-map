// Local isolated UI contract probe, not a Native/Capacitor or real-device gate.
import { mkdir } from 'node:fs/promises'
import { homedir } from 'node:os'
import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? `${homedir()}/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs`)

const base = 'http://127.0.0.1:5208'
const output = new URL('../reports/photo-delete-evidence/', import.meta.url).pathname
await mkdir(output, { recursive: true })
const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true })
try {
  const page = await browser.newPage({ viewport: { width: 393, height: 852 } })
  await page.route('**/*', async route => {
    const url = new URL(route.request().url())
    if (url.origin !== base) return route.abort()
    if (url.pathname === '/__photo-delete-smoke') return route.fulfill({ contentType: 'text/html', body: '<html><body><div id="test-root"></div></body></html>' })
    if (url.pathname === '/src/platform/tasteMapPlatformResolver.ts') return route.fulfill({ contentType: 'application/javascript', body: 'export const resolveTasteMapPlatform = () => window.__photoPlatform; export const shouldRenderHybridShell = () => false;' })
    await route.continue()
  })
  await page.goto(`${base}/__photo-delete-smoke`)
  await page.evaluate(async () => {
    const RefreshRuntime = (await import('/@react-refresh')).default
    RefreshRuntime.injectIntoGlobalHook(window)
    window.$RefreshReg$ = () => {}
    window.$RefreshSig$ = () => type => type
    window.__vite_plugin_react_preamble_installed__ = true
    await import('/src/styles/global.css')
    const reactModule = await import('/node_modules/.vite/deps/react.js')
    const React = reactModule.default ?? reactModule
    const clientModule = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { createRoot } = clientModule.default ?? clientModule
    const { RestaurantUserPhotos } = await import('/src/components/RestaurantUserPhotos.tsx')
    const { db } = await import('/src/db/appDb.ts')
    const { CURRENT_USER_ID } = await import('/src/db/social.ts')
    const { deleteOwnPhoto } = await import('/src/services/photoSync.ts')
    const { cachePhotoBlob } = await import('/src/services/photoAssets.ts')
    window.__deletedCalls = []
    window.__photoPlatform = {
      restaurant: { get: async () => ({ deletablePhotoIDs: window.__owner ? ['test-owner-photo'] : [] }) },
      photo: { discard: async id => { await deleteOwnPhoto(id); window.__deletedCalls.push(id) } },
      events: { subscribe: async () => ({ remove: async () => {} }) },
    }
    window.__owner = true
    const canvas = document.createElement('canvas'); canvas.width = 400; canvas.height = 300
    const ctx = canvas.getContext('2d'); ctx.fillStyle = '#e4bd79'; ctx.fillRect(0,0,400,300)
    ctx.fillStyle = '#3a3026'; ctx.font = '24px sans-serif'; ctx.fillText('TEST PHOTO — NOT USER DATA', 15,150)
    const source = canvas.toDataURL()
    const blob = await new Promise(resolve => canvas.toBlob(resolve))
    for (const id of ['test-owner-photo', 'test-other-photo']) {
      await db.photos.put({ id, userId: id === 'test-owner-photo' ? CURRENT_USER_ID : 'other-owner',
        localState: 'synced', syncStatus: 'synced', deletedAt: null })
      await cachePhotoBlob(id, blob)
    }
    window.__photoRoot = createRoot(document.getElementById('test-root'))
    window.__renderPhotos = (photos = [
        { photoId: 'test-owner-photo', source }, { photoId: 'test-other-photo', source },
      ]) => window.__photoRoot.render(React.createElement(RestaurantUserPhotos, {
      restaurantID: 'test-restaurant', restaurantName: '测试餐厅', photos,
    }))
    window.__renderPhotos()
  })
  await page.getByRole('button', { name: '查看测试餐厅用户实拍 1' }).click()
  await page.getByRole('button', { name: '照片更多操作' }).click()
  await page.getByRole('button', { name: '删除照片', exact: true }).click()
  await page.getByText('将从 Taste Map 中删除，不会删除系统相册中的原照片。', { exact: true }).waitFor()
  await page.screenshot({ path: `${output}browser-owner-confirmation.png`, fullPage: true })
  await page.getByRole('button', { name: '确认删除', exact: true }).click()
  await page.waitForFunction(() => !document.querySelector('.restaurant-photo-preview'))
  assert.deepEqual(await page.evaluate(() => window.__deletedCalls), ['test-owner-photo'])
  assert.equal(await page.getByRole('button', { name: /^查看测试餐厅用户实拍/ }).count(), 1)
  await page.screenshot({ path: `${output}browser-after-local-delete.png`, fullPage: true })
  await page.getByRole('button', { name: '查看测试餐厅用户实拍 1' }).click()
  await page.waitForTimeout(100)
  assert.equal(await page.getByRole('button', { name: '照片更多操作' }).count(), 0)
  assert.equal(await page.getByRole('button', { name: '删除照片', exact: true }).count(), 0)
  await page.screenshot({ path: `${output}browser-other-owner-readonly.png`, fullPage: true })
  await page.evaluate(() => window.__renderPhotos([]))
  await page.waitForFunction(() => !document.querySelector('.restaurant-photo-preview'))
  await page.reload()
  const persisted = await page.evaluate(async () => {
    const { db } = await import('/src/db/appDb.ts')
    const { resolvePhotoSource } = await import('/src/services/photoAssets.ts')
    return { deleted: Boolean((await db.photos.get('test-owner-photo'))?.deletedAt),
      source: await resolvePhotoSource(null, 'test-owner-photo'),
      otherDeleted: Boolean((await db.photos.get('test-other-photo'))?.deletedAt) }
  })
  assert.deepEqual(persisted, { deleted: true, source: null, otherDeleted: false })
  console.log('PASS: owner confirmation → discard exactly once → immediate hide; other-owner no delete control. Browser fixture only; no external requests.')
} finally { await browser.close() }
