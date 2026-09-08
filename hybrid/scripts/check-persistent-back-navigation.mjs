import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage()
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { flushSync } = (await import('/node_modules/.vite/deps/react-dom.js')).default
    const { HybridBackButton, PersistentPageNavigation } = await import('/src/components/TasteMapHybridShared.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    await import('/src/components/tasteMapRestaurantAcquisitionShared.css')
    document.getElementById('root').remove()
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    window.backClicks = 0
    window.showBackProbe = ({ className, route, safeTop, overlay }) => {
      document.documentElement.style.setProperty('--tm-safe-top', `${safeTop}px`)
      const navigationClass = className.includes('public-user-profile--subpage') ? 'public-user-profile__subhead'
        : className.includes('public-user-profile') ? 'public-user-profile__top'
        : className.includes('taste-footprints') ? 'taste-footprints__page-header'
        : className.includes('account-privacy-page') ? '' : null
      const onBack = () => window.backClicks++
      const navigation = navigationClass !== null
        ? React.createElement(PersistentPageNavigation, { as: 'header', className: navigationClass },
          React.createElement('button', { 'aria-label': '返回上一页', onClick: onBack }, '←'),
          React.createElement('div', null, React.createElement('h1', null, 'Existing page title')),
          React.createElement('span', null))
        : React.createElement(HybridBackButton, { onBack })
      const content = React.createElement('main', { className, key: className },
          navigation,
          React.createElement('div', { style: { height: 3200, background: 'linear-gradient(white, #90b0c0)' } }, 'Long-content scroll probe'))
      flushSync(() => root.render(React.createElement('div', { className: 'tm-hybrid-shell', 'data-route': route },
        overlay ? React.createElement('section', { className: 'app-shared-surface-overlay' },
          React.createElement('button', { className: 'app-shared-surface-overlay__close', 'aria-label': '关闭设置' }, '关闭'), content) : content)))
      window.scrollTo(0, 0)
    }
  })
  let checks = 0
  for (const width of [360, 402, 900]) for (const colorScheme of ['light', 'dark']) {
    await page.setViewportSize({ width, height: 874 })
    await page.emulateMedia({ colorScheme })
    for (const [className, route, safeTop, overlay = false] of [
      ['tm-hybrid-detail', 'restaurant', 62],
      ['tm-hybrid-page', 'settings', 62],
      ['tm-hybrid-page tm-hybrid-add', 'add', 62],
      ['tm-hybrid-page', 'analytics', 0],
      ['app-restaurant-detail', 'restaurant', 0],
      ['social-page public-user-profile', 'profile', 0],
      ['social-page public-user-profile public-user-profile--subpage', 'profile', 0],
      ['social-page account-privacy-page', 'profile', 0],
      ['taste-footprints taste-footprints--page', 'profile', 0],
      ['social-page account-privacy-page', 'profile', 0, true],
    ]) {
      await page.evaluate(args => window.showBackProbe(args), { className, route, safeTop, overlay })
      await page.evaluate(() => Promise.all(document.querySelector('main').getAnimations({ subtree: true }).map(animation => animation.finished.catch(() => {}))))
      for (const scroll of [0, 800, 1800, 9999]) {
        await page.evaluate(({ scroll, className, overlay }) => {
          if (overlay) document.querySelector('.app-shared-surface-overlay').scrollTop = scroll
          else if (className === 'app-restaurant-detail') document.querySelector('main').scrollTop = scroll
          else window.scrollTo(0, scroll)
        }, { scroll, className, overlay })
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
        const back = page.getByRole('button', { name: '返回上一页', exact: true })
        assert.equal(await back.count(), 1)
        const box = await back.boundingBox()
        assert.ok(box && box.y >= safeTop - 1 && box.y < 125, `${className}: visible below status bar at ${scroll}: ${JSON.stringify(box)}`)
        // DOM rectangles can differ by sub-micro pixels after transform animation.
        assert.ok(box.width >= 44 - 0.001 && box.height >= 44 - 0.001, `${className}: 44-point hit target at ${width}/${colorScheme}/${scroll}: ${JSON.stringify(box)}`)
        const hittable = await back.evaluate(button => {
          const box = button.getBoundingClientRect()
          return button.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
        })
        assert.equal(hittable, true, `${className}: content must not cover the arrow`)
        if (overlay) assert.equal(await page.getByRole('button', { name: '关闭设置', exact: true }).evaluate(button => {
          const box = button.getBoundingClientRect()
          return button.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
        }), true, 'Browser overlay close must stay above its nested page navigation')
        await back.click()
        checks++
      }
    }
  }
  assert.equal(await page.evaluate(() => window.backClicks), checks)
  console.log(`PASS persistent back geometry/hit/dispatch: ${checks} checks across widths, themes, safe areas, document and nested scrollers`)
} finally { await browser.close() }
