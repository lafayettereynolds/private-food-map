import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  await page.goto(process.env.TASTEMAP_FILTER_TEST_URL ?? 'http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    await import('/src/hybrid/app/hybridShell.css')
    await import('/src/components/tasteMapDiscoveryShared.css')
    await import('/src/components/myMapBrowsePage.css')
    await import('/src/components/tasteMapRestaurantAcquisitionShared.css')
    document.getElementById('root').remove()
    // Isolated CSS probe only: the installed UI test exercises real page routes.
    const shell = document.body.appendChild(document.createElement('div'))
    shell.className = 'tm-hybrid-shell'
    shell.innerHTML = '<div hidden class="profile-page profile-dashboard--owner"></div><div hidden class="tm-hybrid-discovery"></div><main id="canvas-probe"></main>'
  })
  const surfaces = {
    profile: ['profile-page profile-dashboard--owner', '--color-surface'],
    discovery: ['tm-discovery-page__header', '--tm-browse-chrome-background'],
    activity: ['tm-discovery-page__header', '--tm-browse-chrome-background'],
    map: ['tm-my-map__controls', '--tm-browse-chrome-background'],
    add: ['tm-hybrid-page tm-hybrid-add', '--tm-acquisition-surface'],
    settings: ['tm-hybrid-page tm-hybrid-settings', '--color-background'],
    restaurant: ['tm-hybrid-detail', '--color-background'],
    lists: ['tm-hybrid-page', '--color-background'],
    roulette: ['tm-hybrid-page', '--color-background'],
    analytics: ['tm-hybrid-page', '--color-background'],
    premium: ['tm-hybrid-page', '--color-background'],
  }
  for (const width of [375, 402]) {
    await page.setViewportSize({ width, height: 874 })
    for (const colorScheme of ['light', 'dark']) {
      await page.emulateMedia({ colorScheme })
      for (const safeTop of [0, 62]) {
        for (const route of [...Object.keys(surfaces), 'profile', 'settings', 'profile']) {
          const [className, token] = surfaces[route]
          const result = await page.evaluate(({ route, className, token, safeTop }) => {
            const shell = document.querySelector('.tm-hybrid-shell')
            shell.dataset.route = route
            shell.style.setProperty('--tm-safe-top', `${safeTop}px`)
            const probe = document.getElementById('canvas-probe')
            probe.className = className
            if (route === 'discovery' || route === 'activity') {
              probe.className = 'tm-hybrid-discovery'
              probe.innerHTML = '<header class="tm-discovery-page__header"></header>'
            } else probe.replaceChildren()
            const expectedProbe = document.createElement('span')
            expectedProbe.style.backgroundColor = `var(${token})`
            shell.appendChild(expectedProbe)
            const expected = getComputedStyle(expectedProbe).backgroundColor
            expectedProbe.remove()
            const top = getComputedStyle(shell).backgroundColor
            const content = getComputedStyle(probe.firstElementChild ?? probe).backgroundColor
            return { top, content, expected, html: getComputedStyle(document.documentElement).backgroundColor, body: getComputedStyle(document.body).backgroundColor, paddingTop: getComputedStyle(shell).paddingTop }
          }, { route, className, token, safeTop })
          assert.equal(result.top, result.expected, `${route} active canvas (${colorScheme})`)
          assert.equal(result.html, result.top, `${route} document canvas`)
          assert.equal(result.body, result.top, `${route} body canvas`)
          assert.equal(result.paddingTop, `${safeTop}px`, 'safe-area geometry is preserved')
          if (result.content !== 'rgba(0, 0, 0, 0)') assert.equal(result.content, result.top, `${route} seam`)
        }
        console.log(`PASS ${width}/${colorScheme}/safe-top-${safeTop}: all 11 routes and repeated profile/settings return; hidden routes do not leak color`)
      }
    }
  }
} finally { await browser.close() }
