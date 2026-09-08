import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { AccountPrivacyPage } = await import('/src/components/ProfilePage.tsx')
    const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
    await import('/src/hybrid/app/hybridShell.css')
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    window.savedProfiles = []
    window.saveMode = 'success'
    window.editorUser = { ...fixture.profile.user, nickname: '返回测试', city: '杭州', bio: '', avatarImageData: null, avatarPhotoId: null, avatarPresetId: 'polar-bear', mapSharingEnabled: true, mapVisibility: 'public' }
    const render = () => root.render(React.createElement(AccountPrivacyPage, {
      user: window.editorUser,
      onBack() {},
      async onSave(changes) {
        if (window.saveMode === 'pending') await new Promise((resolve, reject) => { window.finishSave = resolve; window.failSave = () => reject(new Error('保存失败，请重试')) })
        window.savedProfiles.push(changes)
        window.editorUser = { ...window.editorUser, ...changes }
        render()
      },
    }))
    render()
  })
  const dialog = page.getByRole('dialog')
  const open = async label => {
    await page.locator('.account-setting-button').filter({ has: page.getByText(label, { exact: true }) }).click()
    await dialog.waitFor()
    await dialog.evaluate(element => Promise.all(element.getAnimations({ subtree: true }).map(animation => animation.finished.catch(() => {}))))
  }
  let checks = 0
  for (const width of [375, 402]) for (const colorScheme of ['light', 'dark']) for (const label of ['编辑资料', '显示名称', '主页可见范围']) {
    await page.setViewportSize({ width, height: 874 })
    await page.emulateMedia({ colorScheme })
    await open(label)
    const back = dialog.getByRole('button', { name: '返回上一页', exact: true })
    assert.equal(await back.count(), 1)
    assert.equal(await dialog.getByRole('button', { name: /^(取消|关闭)$/ }).count(), 0)
    const box = await back.boundingBox()
    assert.ok(box.width >= 43.99 && box.height >= 43.99, `${label}/${width}/${colorScheme}: ${JSON.stringify(box)}`)
    assert.equal(await back.evaluate(button => { const b = button.getBoundingClientRect(); return button.contains(document.elementFromPoint(b.x + b.width / 2, b.y + b.height / 2)) }), true)
    if (label !== '主页可见范围') await dialog.getByLabel('显示名称', { exact: true }).fill('不应保存')
    else await dialog.getByRole('button', { name: '仅自己', exact: true }).click()
    await back.click()
    await dialog.waitFor({ state: 'detached' })
    assert.equal(await page.evaluate(() => window.savedProfiles.length), 0)
    assert.equal(await page.evaluate(() => window.editorUser.nickname), '返回测试')
    checks++
  }
  await page.emulateMedia({ colorScheme: 'light' })
  await open('编辑资料')
  await page.screenshot({ path: '/tmp/tastemap-profile-editor-single-back-browser.png', animations: 'disabled' })
  assert.equal(await dialog.getByLabel('显示名称', { exact: true }).inputValue(), '返回测试')
  await dialog.getByRole('button', { name: '返回上一页' }).click()
  await open('显示名称')
  await dialog.getByLabel('显示名称', { exact: true }).fill('已保存的名称')
  await page.evaluate(() => { window.saveMode = 'pending' })
  await dialog.getByRole('button', { name: '保存资料', exact: true }).click()
  assert.equal(await dialog.getByRole('button', { name: '返回上一页' }).isDisabled(), true)
  await page.keyboard.press('Escape')
  assert.equal(await dialog.count(), 1, 'Pending save must retain editor')
  await page.evaluate(() => window.failSave())
  await dialog.getByText('保存失败，请重试', { exact: true }).waitFor()
  assert.equal(await dialog.getByRole('button', { name: '返回上一页' }).isEnabled(), true)
  assert.equal(await dialog.getByLabel('显示名称', { exact: true }).inputValue(), '已保存的名称')
  await page.evaluate(() => { window.saveMode = 'success' })
  await dialog.getByRole('button', { name: '保存资料', exact: true }).click()
  await dialog.waitFor({ state: 'detached' })
  const saved = await page.evaluate(() => window.savedProfiles)
  assert.equal(saved.length, 1)
  assert.equal(saved[0].nickname, '已保存的名称')
  assert.equal(saved[0].city, '杭州')
  assert.equal(Object.hasOwn(saved[0], 'mapVisibility'), false, 'Name-only editor must not alter privacy')
  console.log(`PASS ${checks} real-component layout/discard variants; save pending, error, retry, and unchanged unrelated fields`)
} finally { await browser.close() }
