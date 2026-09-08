import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  for (const width of [375, 402]) {
    const page = await browser.newPage({ viewport: { width, height: 874 } })
    await page.goto(process.env.TASTEMAP_PROBE_URL ?? 'http://127.0.0.1:4179', { waitUntil: 'networkidle' })
    await page.evaluate(async () => {
      const React = (await import('/node_modules/.vite/deps/react.js')).default
      const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
      const { HybridVisitEditorPage } = await import('/src/hybrid/app/HybridVisitEditorPage.tsx')
      const { ModalShell } = await import('/src/components/ModalShell.tsx')
      const fixture = (await import('/hybrid/fixtures/profile-restaurant-rich.json')).default
      await import('/src/hybrid/app/hybridShell.css')
      document.getElementById('root').remove()
      document.documentElement.style.setProperty('--tm-safe-top', '62px')
      document.documentElement.style.setProperty('--tm-safe-bottom', '34px')
      const viewport = new EventTarget()
      viewport.height = 874; viewport.offsetTop = 0
      Object.defineProperty(window, 'visualViewport', { value: viewport, configurable: true })
      window.keyboard = (height, offsetTop = 0) => {
        viewport.height = height; viewport.offsetTop = offsetTop
        viewport.dispatchEvent(new Event('resize'))
        viewport.dispatchEvent(new Event('scroll'))
      }
      const root = createRoot(document.body.appendChild(document.createElement('div')))
      const restaurant = fixture.restaurants[0]
      const visit = { ...restaurant.visits[0], restaurantId: restaurant.id, note: '保留文字选中和复制粘贴' }
      restaurant.visits = [visit]
      const platform = {
        profile: { getCurrent: async () => ({ restaurants: [restaurant], visits: [visit] }) },
        restaurant: { get: async () => ({ restaurant, editableVisitIDs: [visit.id], capabilities: { canRecordVisit: true } }) },
      }
      window.showModalProbe = (nested = false, show = true) => root.render(React.createElement('div', { className: 'tm-hybrid-shell', 'data-route': 'visitEdit' },
        React.createElement('nav', { className: 'tm-hybrid-bottom-nav' }, '地图 发现 我的'),
        show ? React.createElement(HybridVisitEditorPage, { key: 'editor', platform, visitID: visit.id, restaurants: [], visits: [], onClose: () => {}, onSaved: () => {} }) : null,
        nested ? React.createElement(ModalShell, { title: '子层输入', onClose: () => {} }, React.createElement('label', { className: 'field' }, '城市', React.createElement('input', { defaultValue: '上海' }))) : null))
      window.showModalProbe()
    })
    await page.getByRole('heading', { name: '编辑到访记录', exact: true }).waitFor()
    const measure = () => page.evaluate(() => {
      const modal = document.querySelector('.modal')
      const header = document.querySelector('.modal-header')
      const footer = document.querySelector('.sticky-form-action-bar')
      const content = document.querySelector('.sticky-action-form__content')
      return {
        top: modal.getBoundingClientRect().top,
        headerTop: header.getBoundingClientRect().top,
        footerBottom: footer.getBoundingClientRect().bottom,
        bottom: modal.getBoundingClientRect().bottom,
        width: modal.getBoundingClientRect().width,
        contentHeight: content.clientHeight,
        nav: getComputedStyle(document.querySelector('.tm-hybrid-bottom-nav')).visibility,
        fonts: [...modal.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=range]), textarea, select')].map(input => parseFloat(getComputedStyle(input).fontSize)),
      }
    })
    await page.waitForTimeout(250)
    let metrics = await measure()
    assert(metrics.headerTop >= 62)
    assert(metrics.fonts.every(font => font >= 16), JSON.stringify(metrics.fonts))
    assert.equal(metrics.nav, 'hidden')
    const note = page.getByRole('textbox', { name: '到访笔记', exact: true })
    await note.focus()
    for (const [height, offset] of [[440, 0], [390, 28]]) {
      await page.evaluate(([h, y]) => window.keyboard(h, y), [height, offset])
      await page.waitForTimeout(60)
      metrics = await measure()
      assert(metrics.headerTop >= offset + 62, JSON.stringify(metrics))
      assert(metrics.bottom <= offset + height + 1, JSON.stringify(metrics))
      assert(metrics.footerBottom <= offset + height + 1, JSON.stringify(metrics))
      assert(metrics.contentHeight > 80, JSON.stringify(metrics))
      assert(metrics.width <= width)
      assert(await note.evaluate(input => {
        const field = input.getBoundingClientRect()
        const scroller = input.closest('.sticky-action-form__content').getBoundingClientRect()
        return field.top >= scroller.top - 1 && field.bottom <= scroller.bottom + 1
      }), 'focused field stays inside its form scroller, above Save')
    }
    assert.equal(await note.evaluate(input => getComputedStyle(input).userSelect), 'text')
    await note.evaluate(input => input.setSelectionRange(0, 4))
    assert.equal(await note.evaluate(input => input.selectionEnd - input.selectionStart), 4)
    await page.screenshot({ path: `/tmp/tastemap-modal-keyboard-${width}.png` })
    await page.evaluate(() => window.keyboard(874))
    await page.waitForTimeout(60)
    assert((await measure()).headerTop >= 62)
    await page.evaluate(() => window.showModalProbe(true))
    await page.getByRole('heading', { name: '子层输入', exact: true }).waitFor()
    await page.evaluate(() => window.showModalProbe(false))
    assert.equal(await page.evaluate(() => document.body.classList.contains('modal-open')), true)
    await page.evaluate(() => window.showModalProbe(false, false))
    await page.waitForFunction(() => !document.body.classList.contains('modal-open'))
    assert.equal(await page.locator('.tm-hybrid-bottom-nav').evaluate(nav => getComputedStyle(nav).visibility), 'visible')
    await page.close()
  }
  console.log('PASS shared ModalShell: 375/402, safe top 62, keyboard heights/offsets, sticky Save, input >=16, selection preserved, nested modal lock/restoration')
} finally { await browser.close() }
