import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 650 } })
  const errors = []; page.on('pageerror', error => errors.push(error.message))
  await page.goto('http://127.0.0.1:4179')
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { FoodLibraryArtwork } = await import('/src/visuals/FoodLibraryArtwork.tsx')
    document.getElementById('root').remove()
    const container = document.body.appendChild(document.createElement('div'))
    container.style.cssText = 'display:grid;grid-template-columns:repeat(4,1fr);gap:12px;padding:16px;background:#fff;'
    createRoot(container).render(React.createElement(React.Fragment, null,
      ...['桂雨咖啡', '河岸牛排馆', '兰州拉面', '春日泰味', '青岚寿司', '山茶烘焙', '秋水韩餐', '野火烧鸟'].map(name =>
        React.createElement('figure', { key: name, style: { margin: 0 } },
          React.createElement('div', { style: { height: 230 } }, React.createElement(FoodLibraryArtwork, { name })),
          React.createElement('figcaption', null, name))))
    )
  })
  await page.locator('[data-food-library-artwork="coffee"]').waitFor()
  assert.deepEqual(await page.locator('[data-food-library-artwork]').evaluateAll(items => items.map(item => item.dataset.foodLibraryArtwork)),
    ['coffee', 'steak', 'beef-noodles', 'thai', 'sushi', 'croissant', 'korean', 'yakitori'])
  for (const href of await page.locator('svg image').evaluateAll(images => [...new Set(images.map(image => image.getAttribute('href')))])) {
    const response = await page.request.get(`http://127.0.0.1:4179${href}`)
    assert.equal(response.status(), 200)
    assert.ok((await response.body()).length > 100_000)
  }
  await page.evaluate(async () => {
    await Promise.all([...document.querySelectorAll('svg image')].map(async element => {
      const image = new Image(); image.src = element.getAttribute('href'); await image.decode()
    }))
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
  })
  await page.screenshot({ path: '/tmp/tastemap-food-library-render.png' })
  assert.deepEqual(errors, [])
  console.log('PASS: eight cuisine/name matches render original supplied assets with explicit illustration provenance.')
} finally { await browser.close() }
