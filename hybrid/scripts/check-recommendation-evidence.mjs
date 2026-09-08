import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  for (const width of [375, 430]) for (const colorScheme of ['light', 'dark']) {
    const page = await browser.newPage({ viewport: { width, height: 932 }, colorScheme })
    const errors = []
    page.on('pageerror', error => errors.push(error.message))
    await page.goto(process.env.TASTEMAP_UI_TEST_URL ?? 'http://127.0.0.1:4179')
    await page.evaluate(async () => {
      const React = (await import('/node_modules/.vite/deps/react.js')).default
      const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
      const { RecommendationEvidence } = await import('/src/components/RecommendationEvidence.tsx')
      const { TasteMapActivityCardFrame } = await import('/src/components/TasteMapDiscoveryShared.tsx')
      await import('/src/styles/global.css')
      document.getElementById('root')?.remove()
      const host = document.body.appendChild(document.createElement('div'))
      host.style.padding = '20px'
      const root = createRoot(host)
      const user = { userId: 'visible-fixture', displayName: '可见记录测试用户' }
      const base = { id: 'fixture', mode: 'for_you', restaurant: { name: '隔离渲染测试 · 河岸餐厅' }, sourceUser: { name: '可见记录测试用户' }, reason: '', reasons: [
        { code: 'TASTE_TAG_MATCH', text: '与你给过9分的「参考餐厅」在餐厅类型、人均消费上接近', evidence: { sampleCount: 1, referenceRestaurantID: 'reference', dimensions: ['餐厅类型', '人均消费'] } },
        { code: 'HIGH_CUISINE_MATCH', text: '你过去 5 家相关餐厅的平均评分为 8.6/10', evidence: { sampleCount: 5, meanOutOfTen: 8.6 } },
        { code: 'REPEAT_VISIT_PATTERN', text: '有 2 家同类餐厅曾在不同日期再次到访', evidence: { sampleCount: 2 } },
        { code: 'PRICE_RANGE_MATCH', text: '第四条不得显示' },
      ] }
      window.setEvidenceMode = mode => {
        const item = mode === 'similar' ? { ...base, id: mode, mode: 'similar_taste', reasons: [{ code: 'SIMILAR_USERS', text: '与你共同评过5家餐厅，双方对高低分的判断较接近。' }], tasteEvidence: { evidenceState: 'forming', sharedRestaurantCount: 5, supporterCount: 2, aggregation: 'equal_user_mean', latestVisibleVisitAt: '2026-09-07', records: Array.from({ length: 8 }, (_, i) => ({ user, visitId: `record-${i}`, visitedAt: `2026-09-0${i + 1}`, rating: i === 0 ? null : 4.25 })) } }
          : mode === 'missing' ? { ...base, id: mode, reasons: [{ code: 'LEGACY', text: '旧接口的原始推荐理由' }] }
            : mode === 'empty' ? { ...base, id: mode, reasons: [] } : base
        root.render(React.createElement(TasteMapActivityCardFrame, { variant: 'recommendation', header: React.createElement('h2', null, item.restaurant.name), body: React.createElement(RecommendationEvidence, { item }) }))
      }
      window.setEvidenceMode('for_you')
    })
    const trigger = page.getByRole('button', { name: '查看依据', exact: true })
    await trigger.waitFor()
    assert((await trigger.boundingBox()).height >= 44)
    assert.equal(await page.getByText('第四条不得显示').count(), 0)
    assert.equal(await page.locator('.tm-activity-card__recommendation-reasons > li').count(), 3)
    for (const mode of ['for_you', 'similar', 'missing']) {
      await page.evaluate(mode => window.setEvidenceMode(mode), mode)
      await trigger.click()
      const dialog = page.getByRole('dialog', { name: '推荐依据' })
      await dialog.waitFor()
      await page.evaluate(() => document.getAnimations().forEach(animation => animation.finish()))
      assert.equal(await page.getByRole('button', { name: '关闭', exact: true }).count(), 1)
      assert((await page.getByRole('button', { name: '关闭', exact: true }).boundingBox()).height >= 44)
      const text = await dialog.innerText()
      if (mode === 'for_you') { assert(text.includes('8.6 / 10')); assert(text.includes('尚未提供逐店、逐次到访明细')) }
      if (mode === 'similar') { assert(text.includes('8.5 / 10')); assert(text.includes('未提供有效评分')); assert.equal(await dialog.locator('.tm-recommendation-evidence__records > li').count(), 8) }
      if (mode === 'missing') assert(text.includes('尚未提供样本与记录明细'))
      assert(await dialog.evaluate(el => el.scrollWidth <= el.clientWidth + 1))
      await page.screenshot({ path: `/private/tmp/tastemap-recommendation-evidence-${mode}-${width}-${colorScheme}.png` })
      await page.keyboard.press('Escape')
      await dialog.waitFor({ state: 'detached' })
      await page.waitForFunction(() => document.activeElement?.classList.contains('tm-recommendation-evidence__trigger'))
      assert(await trigger.evaluate(el => document.activeElement === el))
      assert.equal(await page.locator('body.modal-open').count(), 0)
    }
    await page.evaluate(() => window.setEvidenceMode('empty'))
    await trigger.waitFor({ state: 'detached' })
    assert.deepEqual(errors, [])
    console.log(`PASS recommendation evidence ${width}px ${colorScheme}: max 3 visible reasons, history / same-taste / missing / empty, close, focus, no horizontal overflow`)
    await page.close()
  }
} finally { await browser.close() }
