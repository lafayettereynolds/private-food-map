import assert from 'node:assert/strict'
const { chromium } = await import(process.env.TASTEMAP_PLAYWRIGHT_MODULE ?? 'playwright')
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
  await page.goto('http://127.0.0.1:4179', { waitUntil: 'networkidle' })
  const result = await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const { createRoot } = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { flushSync } = (await import('/node_modules/.vite/deps/react-dom.js')).default
    const { NativeMapSurface } = await import('/src/components/NativeMapSurface.tsx')
    const container = document.body.appendChild(document.createElement('div'))
    const root = createRoot(container)
    const requests = []
    const replies = []
    const errors = []
    const frames = new Map()
    let frameID = 0
    const originalRAF = window.requestAnimationFrame
    const originalCancel = window.cancelAnimationFrame
    const originalViewport = Object.getOwnPropertyDescriptor(window, 'visualViewport')
    const visualViewport = Object.assign(new EventTarget(), { width: 402, height: 874, offsetLeft: 0, offsetTop: 0 })
    Object.defineProperty(window, 'visualViewport', { configurable: true, value: visualViewport })
    window.requestAnimationFrame = callback => { frames.set(++frameID, callback); return frameID }
    window.cancelAnimationFrame = id => frames.delete(id)
    const props = {
      active: true, interactionBlocked: false,
      platform: { map: { updateNativeSurface: request => {
        requests.push(request)
        return new Promise(resolve => replies.push(() => resolve({ requestID: request.requestID, surface: 'mapkit', persistent: true })))
      } } },
      restaurants: [], images: {}, selectedRestaurantID: null, scope: 'visited', filters: {}, sort: 'recent', search: '',
      cameraFitKey: 'preserved-camera', currentUser: { avatarPresetId: 'polar-bear' }, tasteDataProgress: null,
      overlayRevision: '', onError: error => errors.push(error),
    }
    const render = changes => flushSync(() => root.render(React.createElement(NativeMapSurface, { ...props, ...changes })))
    const paint = () => { const work = [...frames.values()]; frames.clear(); work.forEach(callback => callback(0)) }
    const check = (condition, message) => { if (!condition) throw new Error(message) }
    try {
      render({ active: true })
      render({ active: false })
      check(requests.length === 1 && !requests[0].visible, 'Leaving before first paint must hide synchronously')
      paint()
      check(requests.every(request => !request.visible), 'Cancelled frame must not re-show the map')
      render({ active: true }); paint()
      const initialFrame = requests.at(-1).frame
      Object.assign(visualViewport, { width: 201, height: 420, offsetLeft: 18, offsetTop: 140 })
      visualViewport.dispatchEvent(new Event('resize')); paint()
      check(requests.at(-1).viewportWidth === 201 && requests.at(-1).viewportHeight === 420,
        'Visual viewport resize must publish its actual dimensions without a window resize')
      check(requests.at(-1).frame.x === initialFrame.x - 18 && requests.at(-1).frame.y === initialFrame.y - 140,
        'Map geometry must be relative to the visual viewport after zoom/focus scrolling')
      Object.assign(visualViewport, { offsetTop: 160 })
      visualViewport.dispatchEvent(new Event('scroll')); paint()
      check(requests.at(-1).frame.y === initialFrame.y - 160,
        'Visual viewport scrolling must move the Native rectangle with React')
      Object.assign(visualViewport, { width: 402, height: 874, offsetLeft: 0, offsetTop: 0 })
      visualViewport.dispatchEvent(new Event('resize')); paint()
      check(requests.at(-1).frame.y === initialFrame.y && requests.at(-1).viewportWidth === 402,
        'Returning from focus/zoom must restore the original geometry')
      for (let index = 0; index < 30; index++) {
        render({ active: true }); paint()
        check(requests.at(-1).visible, 'Return to Map must show the retained surface')
        render(index % 2 ? { active: false } : { interactionBlocked: true })
        check(!requests.at(-1).visible, 'Route, List and React overlays must hide without a paint')
        paint()
        check(!requests.at(-1).visible, 'No scheduled visible update may survive hiding')
      }
      const pendingCount = replies.length
      replies.reverse().forEach(reply => reply())
      await Promise.resolve()
      check(errors.length === 1 && errors[0] === null, 'Only the current request acknowledgement may change error state')
      flushSync(() => root.unmount())
      check(!requests.at(-1).visible, 'Unmount is also hidden')
      return { cycles: 30, requests: requests.length, reversedReplies: pendingCount, passed: true }
    } finally {
      window.requestAnimationFrame = originalRAF
      window.cancelAnimationFrame = originalCancel
      if (originalViewport) Object.defineProperty(window, 'visualViewport', originalViewport)
      else delete window.visualViewport
      container.remove()
    }
  })
  assert.equal(result.passed, true)
  console.log(`PASS actual React NativeMapSurface sender: ${JSON.stringify(result)}`)
} finally { await browser.close() }
