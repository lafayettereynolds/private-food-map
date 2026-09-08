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
    const { ProfilePage, AccountPrivacyPage } = await import('/src/components/ProfilePage.tsx')
    const { TasteMapSettingsPage } = await import('/src/components/TasteMapPremiumSettingsPages.tsx')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/hybrid/app/hybridShell.css')
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    let route = 'profile'
    let user
    const profile = () => ({ ...fixture.profile, user, restaurants: [], visits: [] })
    const platform = {
      kind: 'browser',
      sync: { status: async () => ({ state: 'idle', pendingMutationCount: 0 }) },
      permissions: { status: async () => ({ location: 'notDetermined', camera: 'notDetermined', photoAddOnly: 'notDetermined' }) },
      events: { subscribe: async () => ({ remove: async () => {} }) },
      navigation: { openNative: async request => { window.nativeRequests.push(request) } },
    }
    const navigate = next => { route = next; render() }
    const save = async changes => {
      window.savedProfiles.push(changes)
      user = { ...user, ...changes }
      render()
    }
    const render = () => root.render(route === 'profile'
      ? React.createElement(ProfilePage, { user, onSave: save, onOpenSettings: () => navigate('settings') })
      : route === 'settings'
        ? React.createElement(TasteMapSettingsPage, {
          platform, profile: profile(), onBack: () => navigate('profile'),
          onOpenNativeSettings: window.nativeHandoff ? undefined : request => {
            window.settingsRequests.push(request)
            if (request.route !== 'accountSettings') throw new Error('Unexpected destination')
            navigate('account')
          },
        })
        : React.createElement(AccountPrivacyPage, { user, onSave: save, onBack: () => navigate('settings') }))
    window.resetProfileEntry = (membershipTier, nativeHandoff = false) => {
      user = { ...fixture.profile.user, nickname: '设置入口回归', membershipTier, avatarPhotoId: null, avatarImageData: null, avatarPresetId: 'polar-bear', city: '杭州', mapSharingEnabled: true, mapVisibility: 'public' }
      window.savedProfiles = []
      window.settingsRequests = []
      window.nativeRequests = []
      window.nativeHandoff = nativeHandoff
      navigate('profile')
    }
    window.resetProfileEntry('member')
  })
  const dialog = page.getByRole('dialog')
  const back = () => page.getByRole('button', { name: '返回上一页', exact: true })
  const fullEdit = () => page.locator('.account-setting-button').filter({ has: page.getByText('编辑资料', { exact: true }) })
  const account = () => page.getByRole('button', { name: /账户与安全/ })
  let checks = 0
  for (const membershipTier of ['free', 'member']) for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) {
    await page.setViewportSize({ width, height: 874 })
    await page.emulateMedia({ colorScheme })
    await page.evaluate(tier => window.resetProfileEntry(tier), membershipTier)
    await page.locator('.profile-dashboard__identity h1 > span').filter({ hasText: /^设置入口回归$/ }).waitFor()
    assert.equal(await page.getByRole('button', { name: '编辑资料', exact: true }).count(), 0)
    assert.equal(await page.locator('.profile-edit-button').count(), 0)
    assert.equal(await page.locator('.profile-dashboard__identity-actions').count(), membershipTier === 'member' ? 0 : 1)
    if (membershipTier === 'free') assert.equal(await page.locator('.profile-dashboard__identity-actions button').count(), 1)
    else assert.equal(await page.getByRole('button', { name: '查看 Premium 会员状态', exact: true }).count(), 1)
    assert.deepEqual(await page.locator('.profile-dashboard__counts--primary small').allTextContents(), ['去过', '想去', '总消费'])
    const geometry = await page.evaluate(() => {
      const rect = selector => document.querySelector(selector).getBoundingClientRect()
      const identity = rect('.profile-dashboard__identity')
      const tail = rect(document.querySelector('.profile-dashboard__identity-actions') ? '.profile-dashboard__identity-actions' : '.profile-joined-at')
      const statistics = rect('.profile-dashboard__counts--primary')
      const quick = rect('.profile-quick-actions')
      return { emptyIdentityTail: identity.bottom - tail.bottom, statsBottom: statistics.bottom, quickTop: quick.top, overflow: document.documentElement.scrollWidth - innerWidth }
    })
    assert.ok(geometry.emptyIdentityTail < 2, JSON.stringify(geometry))
    assert.ok(geometry.quickTop >= geometry.statsBottom, JSON.stringify(geometry))
    assert.ok(geometry.overflow <= 1, JSON.stringify(geometry))
    if (width === 402 && colorScheme === 'light') await page.screenshot({ path: `/tmp/tastemap-profile-settings-entry-${membershipTier}.png`, animations: 'disabled' })

    // The existing avatar gesture is preserved, not silently retired with the text button.
    await page.getByRole('button', { name: '编辑个人资料', exact: true }).click()
    await dialog.waitFor()
    await dialog.getByRole('button', { name: '返回上一页', exact: true }).click()
    await dialog.waitFor({ state: 'detached' })
    await page.getByRole('button', { name: '设置', exact: true }).click()
    await account().click()
    assert.deepEqual(await page.evaluate(() => window.settingsRequests), [{ route: 'accountSettings', identifier: undefined }])
    assert.equal(await fullEdit().count(), 1)
    await fullEdit().click()
    await dialog.getByLabel('显示名称', { exact: true }).fill('不应保存')
    await dialog.getByRole('button', { name: '返回上一页', exact: true }).click()
    await dialog.waitFor({ state: 'detached' })
    assert.equal(await page.evaluate(() => window.savedProfiles.length), 0)
    await fullEdit().click()
    assert.equal(await dialog.getByLabel('显示名称', { exact: true }).inputValue(), '设置入口回归')
    await dialog.getByLabel('显示名称', { exact: true }).fill('设置保存成功')
    await dialog.getByRole('button', { name: '保存资料', exact: true }).click()
    await dialog.waitFor({ state: 'detached' })
    await page.getByRole('heading', { name: '账户与安全', exact: true }).waitFor()
    const saved = await page.evaluate(() => window.savedProfiles)
    assert.equal(saved.length, 1)
    assert.equal(saved[0].nickname, '设置保存成功')
    assert.equal(saved[0].city, '杭州')
    await back().click()
    await page.getByRole('heading', { name: '设置', exact: true }).waitFor()
    await back().click()
    await page.locator('.profile-dashboard__identity h1 > span').filter({ hasText: /^设置保存成功$/ }).waitFor()
    assert.equal(await page.getByRole('button', { name: '编辑资料', exact: true }).count(), 0)
    checks++
    console.log(`PASS ${membershipTier}/${width}/${colorScheme}: identity geometry, settings cancel/save/return`)
  }
  await page.evaluate(() => window.resetProfileEntry('member', true))
  await page.getByRole('button', { name: '设置', exact: true }).click()
  await account().click()
  assert.deepEqual(await page.evaluate(() => window.nativeRequests), [{ route: 'accountSettings', identifier: undefined }])
  assert.deepEqual(errors, [])
  console.log(`PASS ${checks} real shared-component Free/Premium, 375/402px, light/dark variants: no text edit or empty row; avatar unchanged; Settings real full-editor cancel/save/back; typed Native account handoff. No installed-device claim.`)
} finally { await browser.close() }
