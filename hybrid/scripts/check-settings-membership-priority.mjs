import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  await page.goto(process.env.TASTEMAP_FILTER_TEST_URL ?? 'http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { TasteMapSettingsPage } = await import('/src/components/TasteMapPremiumSettingsPages.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    document.getElementById('root').style.display = 'none'
    const host = document.body.appendChild(document.createElement('div'))
    host.id = 'membership-order-probe'
    const root = createRoot(host)
    const platform = { kind: 'browser', sync: { status: async () => ({ state: 'idle', pendingMutationCount: 0, lastSuccessfulSyncAt: null }) }, permissions: { status: async () => ({ location: 'notDetermined', camera: 'notDetermined', photoAddOnly: 'notDetermined', canOpenSystemSettings: false }) }, events: { subscribe: async () => ({ remove: async () => {} }) } }
    window.renderMembershipOrder = membershipTier => {
      window.membershipOpenCount = 0
      root.render(React.createElement(TasteMapSettingsPage, { key: membershipTier, platform, profile: { user: { nickname: '设置布局测试', membershipTier }, restaurants: [], visits: [] }, onOpenPremium() { window.membershipOpenCount += 1 } }))
    }
    window.renderMembershipOrder('member')
  })
  const settings = page.locator('#membership-order-probe')
  for (const tier of ['member', 'free']) {
    await page.evaluate(tier => window.renderMembershipOrder(tier), tier)
    const premium = settings.getByRole('button', { name: /^Premium / })
    await premium.waitFor()
    for (const width of [375, 402]) {
      await page.setViewportSize({ width, height: 874 })
      for (const colorScheme of ['light', 'dark']) {
        await page.emulateMedia({ colorScheme })
        const account = await settings.getByRole('button', { name: /^账户与安全/ }).boundingBox()
        const row = await premium.boundingBox()
        const backup = await settings.getByRole('button', { name: /^导出备份/ }).boundingBox()
        assert.ok(account.y + account.height < row.y)
        assert.ok(row.y + row.height < backup.y)
        assert.ok(row.y + row.height < 774, 'membership stays in the first screen without scrolling')
        assert.equal(await premium.count(), 1)
        assert.equal(await settings.getByText('存储与 Premium', { exact: true }).count(), 0)
        console.log(`PASS ${tier}/${width}/${colorScheme}: account → membership → data; membership y=${row.y}, height=${row.height}`)
      }
    }
    await page.emulateMedia({ colorScheme: 'light' })
    await premium.click()
    assert.equal(await page.evaluate(() => window.membershipOpenCount), 1)
    assert.ok((await premium.innerText()).includes(tier === 'member' ? '查看当前权益与订阅管理' : '查看会员能力'))
    await page.screenshot({ path: `/tmp/tastemap-settings-membership-${tier}.png`, animations: 'disabled' })
  }
} finally { await browser.close() }
