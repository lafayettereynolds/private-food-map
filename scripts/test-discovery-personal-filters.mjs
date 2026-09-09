// Isolated local UI probe. Never connects to a real API or reads a real session.
import assert from 'node:assert/strict'
import { homedir } from 'node:os'
const { chromium } = await import(`${homedir()}/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs`)
const origin = 'http://127.0.0.1:5219'
const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true })
try {
  const page = await browser.newPage({ viewport: { width: 393, height: 852 } })
  await page.route('**/*', async route => {
    const url = new URL(route.request().url())
    if (url.origin !== origin) return route.abort()
    if (url.pathname === '/__personal-filter-qa') return route.fulfill({ contentType: 'text/html', body: '<html><body><div id="test-root"></div></body></html>' })
    return route.continue()
  })
  await page.goto(`${origin}/__personal-filter-qa`)
  await page.evaluate(async () => {
    const Refresh = (await import('/@react-refresh')).default
    Refresh.injectIntoGlobalHook(window)
    window.$RefreshReg$ = () => {}; window.$RefreshSig$ = () => type => type
    window.__vite_plugin_react_preamble_installed__ = true
    await import('/src/styles/global.css')
    await import('/src/hybrid/app/hybridShell.css')
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const client = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { createRoot } = client.default ?? client
    const { DiscoveryQueryPanel } = await import('/src/components/DiscoveryQueryPanel.tsx')
    const { normalizeDiscoveryFilters } = await import('/src/contracts/discoveryFilters.ts')
    const { normalizeDiscoverySessionPreferences } = await import('/src/contracts/discoverySessionPreferences.ts')
    createRoot(document.getElementById('test-root')).render(React.createElement(DiscoveryQueryPanel, {
      mode: 'for_you', platform: {}, initial: { city: '杭州', filters: normalizeDiscoveryFilters(), sort: 'recommended', windowDays: 7, preferences: normalizeDiscoverySessionPreferences() },
      onCancel: () => { window.__cancelled = true }, onApply: value => { window.__applied = value },
    }))
  })
  await page.getByLabel('预计喜欢度', { exact: true }).selectOption('8')
  await page.getByLabel('口味匹配度', { exact: true }).selectOption('90')
  await page.getByLabel('筛选排序', { exact: true }).selectOption('predicted_liking')
  assert.equal(await page.getByLabel('大家评分', { exact: true }).count(), 0)
  assert.equal(await page.getByText('大家评分优先', { exact: true }).count(), 0)
  await page.getByRole('button', { name: '应用', exact: true }).click()
  const applied = await page.evaluate(() => window.__applied)
  assert.equal(applied.filters.minimumPredictedLikingOutOfTen, 8)
  assert.equal(applied.filters.minimumTasteMatchPercent, 90)
  assert.equal(applied.filters.minimumPublicScoreOutOfTen, null)
  assert.equal(applied.sort, 'predicted_liking')
  if (process.env.TASTEMAP_QA_SCREENSHOT) {
    await page.getByLabel('口味匹配度', { exact: true }).scrollIntoViewIfNeeded()
    await page.screenshot({ path: process.env.TASTEMAP_QA_SCREENSHOT, fullPage: true })
  }
  await page.getByRole('button', { name: '重置', exact: true }).click()
  assert.equal(await page.getByLabel('预计喜欢度', { exact: true }).inputValue(), '')
  assert.equal(await page.getByLabel('口味匹配度', { exact: true }).inputValue(), '')
  assert.equal(await page.getByLabel('筛选城市', { exact: true }).inputValue(), '杭州')
  await page.getByRole('button', { name: '应用', exact: true }).click()
  const reset = await page.evaluate(() => window.__applied)
  assert.equal(reset.filters.minimumPredictedLikingOutOfTen, undefined)
  assert.equal(reset.filters.minimumTasteMatchPercent, undefined)
  assert.equal(reset.sort, 'recommended')
  console.log('PASS: real controls, independent thresholds, prediction sort, absent public rating, reset/city preservation; local QA only.')
} finally { await browser.close() }
