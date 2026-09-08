import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  page.on('pageerror', error => console.error(error.message))
  await page.route('**/src/services/socialApi.ts*', async route => {
    const response = await route.fetch()
    const source = await response.text()
    const patched = source.replace(/(async function fetchCommunityFeed\([^)]*\)\s*\{)/, '$1 if (window.cardTestFeed) return window.cardTestFeed;')
    assert.notEqual(patched, source)
    await route.fulfill({ response, body: patched })
  })
  await page.goto(process.env.TASTEMAP_CARD_TEST_URL ?? 'http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { HybridDiscoveryPage } = await import('/src/hybrid/app/HybridDiscoveryPage.tsx')
    const { CommunityPage } = await import('/src/components/CommunityPage.tsx')
    await import('/src/hybrid/app/hybridShell.css')
    const fixture = await (await fetch('/hybrid/fixtures/profile-restaurant-rich.json')).json()
    document.getElementById('root').style.display = 'none'
    const root = createRoot(document.body.appendChild(document.createElement('div')))
    const restaurant = { ...fixture.restaurants[0], id: 'test-card-restaurant', name: '口味卡片测试餐厅', city: '杭州', image: { kind: 'foodCategoryVisual', categoryVisualID: 'noodles', stableSeed: 'test-card', exportAllowed: false } }
    const user = { id: 'test-card-user', name: '卡片测试用户', isFollowing: true }
    const interaction = { activityID: 'test-activity', visitID: 'test-visit', authorID: user.id, restaurantID: restaurant.id }
    const reasons = [{ code: 'HIGH_CUISINE_MATCH', text: '偏爱面食' }, { code: 'PRICE_RANGE_MATCH', text: '消费接近' }, { code: 'REPEAT_VISIT_PATTERN', text: '与你多次到访并给出高分的面馆有相近口味，适合这次希望尝试的新鲜风味' }]
    const placement = { id: 'test-card', restaurant, viewerState: 'none', sourceUser: user, activityRating: 4.5, activityVisitedAt: '2026-09-06T00:00:00Z', interaction, likedByViewer: false, likeCount: 12, commentCount: 2, communityRating: { valueOutOfFive: 4.5, sampleCount: 8 }, reasons, reason: reasons[0].text, personalTastePercent: 85, similarityPercent: 80, sharedRestaurantCount: 6, trendWindowDays: 7, uniqueVisitorCount: 8, rank: 1 }
    const activity = { id: 'test-activity', kind: 'visit', eventAt: '2026-09-06T00:00:00Z', user, restaurant, visitID: 'test-visit', interaction, visitRating: 4.5, note: '试过以后留下的真实口味感受。', viewerState: 'none', likedByViewer: false, likeCount: 12, commentCount: 2 }
    const content = { generatedAt: '2026-09-06T00:00:00Z', discovery: { forYou: [{ ...placement, mode: 'for_you', sourceUser: null, activityRating: null, activityVisitedAt: null, interaction: null }], similarTaste: [{ ...placement, mode: 'similar_taste' }], trending: [{ ...placement, mode: 'trending', sourceUser: null, interaction: null }] }, community: { following: [activity], latest: [activity] }, lists: [] }
    window.cardTestFeed = { access: { entitlementTier: 'premium', advancedFiltersEnabled: true, fullExplanationEnabled: true, similarTasteEnabled: true }, items: [{ user: { ...fixture.profile.user, id: user.id }, restaurant, visit: { ...fixture.restaurants[0].visits[0], id: 'test-visit', restaurantId: restaurant.id, rating: 4.5 }, personalTastePercent: 85, primaryReasons: reasons, publicRating: { value: 9, sampleCount: 8 } }] }
    localStorage.setItem('taste-map-community-engagement-v1', JSON.stringify({ 'test-visit': { liked: false, likeCount: 12, comments: ['测试评论一', '测试评论二'] } }))
    window.cardActions = []
    const platform = { kind: 'browser', community: { setLike: async (target, liked) => { window.cardActions.push(['like', target.visitID, liked]); return { likedByViewer: liked, likeCount: liked ? 13 : 12, commentCount: 2 } }, comments: async () => ({ items: [] }) }, navigation: { openNative: async () => {} }, share: { open: async () => window.cardActions.push(['share']) } }
    window.showCardTest = (host, withProbability = false) => {
      const probability = withProbability ? { value: .82, modelVersion: 'test-only-model', calibrationVersion: 'test-only-calibration', calibrationStatus: 'validated', evidenceStatus: 'sufficient', positiveFeedbackDefinition: '用户在到访后明确选择喜欢', definitionVersion: 'test-only-definition', definitionStatus: 'approved', validationSampleCount: 800, validUntil: '2099-09-07T00:00:00Z' } : null
      content.discovery.forYou[0].calibratedLikeProbability = probability
      window.cardTestFeed.items[0].calibratedLikeProbability = probability
      function BrowserPage() {
        const [mode, setMode] = React.useState('for_you')
        return React.createElement(CommunityPage, { mode, onModeChange: setMode, users: [], restaurants: [], candidateRestaurantIds: [], onToggleWant() {}, onMarkVisited() {}, onToggleCandidate() {}, onViewProfile() {} })
      }
      root.render(React.createElement('div', { className: 'tm-hybrid-shell', key: `${host}-${withProbability}` }, host === 'hybrid' ? React.createElement(HybridDiscoveryPage, { content, platform, onOpenRestaurant() {} }) : React.createElement(BrowserPage)))
    }
    window.showCardTest('hybrid')
  })
  for (const host of ['hybrid', 'browser']) {
    await page.evaluate(host => window.showCardTest(host), host)
    await page.getByRole('button', { name: '口味匹配度 85%，查看说明', exact: true }).waitFor().catch(async error => { console.error(host, await page.locator('body').innerText()); throw error })
    assert.equal(await page.locator('[data-recommendation-signal="match"]').evaluate(el => el.style.getPropertyValue('--tm-taste-prediction-color')), await page.evaluate(async () => (await import('/src/types/domain.ts')).scoreColor(8.5)))
    for (const scheme of ['light', 'dark']) {
      await page.emulateMedia({ colorScheme: scheme })
      for (const width of [375, 402]) {
        await page.setViewportSize({ width, height: 874 })
        const metrics = await page.locator('.tm-activity-card').first().evaluate(card => {
          const list = card.querySelector('.tm-activity-card__recommendation-reasons')
          const tags = [...list.children].map(tag => ({ text: tag.textContent, rect: tag.getBoundingClientRect().toJSON(), border: getComputedStyle(tag).borderWidth, before: getComputedStyle(tag, '::before').content, font: getComputedStyle(tag).fontSize, whiteSpace: getComputedStyle(tag).whiteSpace }))
          const buttons = [...card.querySelectorAll('.tm-activity-card__social button')].map(button => ({ rect: button.getBoundingClientRect().toJSON(), border: getComputedStyle(button).borderWidth, radius: getComputedStyle(button).borderRadius, background: getComputedStyle(button).backgroundColor }))
          return { tags, buttons, cardWidth: card.getBoundingClientRect().width, reasonTarget: card.querySelector('.tm-recommendation-reasons-control__open').getBoundingClientRect().toJSON(), list: list.getBoundingClientRect().toJSON(), display: getComputedStyle(list).display, wrap: getComputedStyle(list).flexWrap }
        })
        assert.equal(metrics.display, 'flex'); assert.equal(metrics.wrap, 'wrap')
        assert.equal(metrics.tags.length, 3)
        for (const tag of metrics.tags) { assert.equal(tag.border, '0px'); assert.equal(tag.before, 'none'); assert.equal(tag.font, '11px'); assert.equal(tag.whiteSpace, 'nowrap'); assert.ok(tag.rect.width <= 160 && tag.rect.width < metrics.cardWidth / 2); assert.ok(tag.rect.height <= 24); assert.ok(tag.rect.right <= metrics.list.right + .5) }
        assert.ok(metrics.tags[0].rect.width < metrics.list.width / 2, `${host}: short reasons must hug their text`)
        assert.equal(metrics.tags[0].rect.y, metrics.tags[1].rect.y)
        assert.ok(metrics.tags[2].text.endsWith('…'), `${host}: long evidence visibly indicates its full explanation`)
        assert.ok(metrics.reasonTarget.width >= 44 && metrics.reasonTarget.height >= 44 && metrics.reasonTarget.height <= 52, `${host}: one shared accessible target keeps the row compact`)
        for (const action of metrics.buttons) { assert.ok(action.rect.width >= 44 && action.rect.height >= 44); assert.equal(action.border, '0px'); assert.equal(action.radius, '0px'); assert.equal(action.background, 'rgba(0, 0, 0, 0)') }
        await page.screenshot({ path: `/tmp/tastemap-discovery-${host}-${scheme}-${width}-match.png`, animations: 'disabled' })
        if (width === 402) await page.screenshot({ path: `/tmp/tastemap-discovery-${host}-${scheme}-match.png`, animations: 'disabled' })
      }
    }
    await page.getByRole('button', { name: '查看 3 条完整推荐理由', exact: true }).click()
    const reasonDialog = page.getByRole('dialog', { name: '推荐理由', exact: true })
    await reasonDialog.waitFor()
    assert.ok((await reasonDialog.innerText()).includes('推荐依据'))
    assert.ok(!(await reasonDialog.innerText()).includes('私人餐厅库'))
    assert.ok((await reasonDialog.innerText()).includes('与你多次到访并给出高分的面馆有相近口味，适合这次希望尝试的新鲜风味'))
    assert.equal(await reasonDialog.locator('.tm-recommendation-reasons-full > p').count(), 3)
    await page.screenshot({ path: `/tmp/tastemap-discovery-${host}-full-reasons.png`, animations: 'disabled' })
    await reasonDialog.getByRole('button', { name: '关闭', exact: true }).click()
    await page.getByRole('button', { name: '口味匹配度 85%，查看说明', exact: true }).click()
    const matchDialog = page.getByRole('dialog', { name: '口味匹配度', exact: true })
    await matchDialog.waitFor(); assert.ok((await matchDialog.innerText()).includes('不代表喜欢这家餐厅的概率'))
    assert.ok((await matchDialog.innerText()).includes('推荐说明'))
    assert.ok(!(await matchDialog.innerText()).includes('私人餐厅库'))
    await matchDialog.getByRole('button', { name: '关闭', exact: true }).click()
    await page.getByRole('tab', { name: '同味之选', exact: true }).click()
    const social = page.locator('.tm-activity-card__social').first()
    assert.equal(await social.locator('button').count(), 3)
    assert.equal(await social.locator('.tm-social-action__count').allTextContents().then(items => items.join(',')), '12,2')
    if (host === 'hybrid') {
      await social.getByRole('button', { name: /^点赞/ }).click()
      await social.getByRole('button', { name: /^取消点赞/ }).waitFor()
      assert.equal(await social.locator('.tm-social-action__count').first().innerText(), '13')
      await social.getByRole('button', { name: /^分享/ }).click()
      assert.deepEqual(await page.evaluate(() => window.cardActions), [['like', 'test-visit', true], ['share']])
      await page.screenshot({ path: '/tmp/tastemap-discovery-hybrid-social.png', animations: 'disabled' })
    }
    await page.emulateMedia({ colorScheme: 'light' })
    await page.setViewportSize({ width: 402, height: 874 })
    await page.getByRole('tab', { name: '趋势', exact: true }).click()
    const trendingCard = page.locator('.tm-activity-card').first()
    await trendingCard.waitFor()
    assert.equal(await trendingCard.getByText('近期趋势', { exact: true }).count(), 0)
    assert.equal(await trendingCard.locator('.tm-activity-card__recommendation-tag').count(), 0)
    assert.equal(await trendingCard.locator('.tm-activity-card__rating-summary').count(), 0)
    assert.equal(await trendingCard.locator('[data-activity-region="visit-rating"]').count(), 0)
    assert.equal(await trendingCard.locator('[data-activity-region="restaurant-image"]').count(), 1)
    assert.equal(await trendingCard.locator('[data-activity-region="restaurant-name-address-context"]').count(), 1)
    assert.ok(await trendingCard.locator('[data-activity-region="restaurant-actions"] button').count() >= 3)
    assert.ok((await trendingCard.innerText()).includes('口味卡片测试餐厅'))
    await page.screenshot({ path: `/tmp/tastemap-trending-clean-header-${host}-402.png`, animations: 'disabled' })
    await page.evaluate(host => window.showCardTest(host, true), host)
    await page.getByRole('button', { name: '喜欢概率 82%，查看说明', exact: true }).click()
    const probabilityDialog = page.getByRole('dialog', { name: '喜欢概率', exact: true })
    await probabilityDialog.waitFor(); assert.ok((await probabilityDialog.innerText()).includes('用户在到访后明确选择喜欢'))
    assert.ok((await probabilityDialog.innerText()).includes('test-only-calibration'))
    await probabilityDialog.getByRole('button', { name: '关闭', exact: true }).click()
    assert.equal(await page.locator('[data-recommendation-signal="probability"]').evaluate(el => el.style.getPropertyValue('--tm-taste-prediction-color')), await page.evaluate(async () => (await import('/src/types/domain.ts')).scoreColor(8.2)))
    console.log(`PASS ${host}: light/dark 375/402px actual CSS, short reason excerpts with full accessible explanation and one 44px target, bare social actions/counts, matching/probability explanations`)
  }
} finally { await browser.close() }
