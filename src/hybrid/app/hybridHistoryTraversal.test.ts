import { afterEach, describe, expect, it, vi } from 'vitest'
import { beginHybridHistoryBack } from './hybridHistoryTraversal'

function browserHistory(back = vi.fn()) {
  const events = new EventTarget()
  const target = { history: { back }, addEventListener: events.addEventListener.bind(events), removeEventListener: events.removeEventListener.bind(events) }
  return { target: target as unknown as Pick<Window, 'history' | 'addEventListener' | 'removeEventListener'>, back, events }
}

afterEach(() => vi.useRealTimers())

describe('Hybrid Back traversal ordering', () => {
  it('starts visible Back immediately but keeps an early Native reply behind the real popstate', async () => {
    vi.useFakeTimers()
    const browser = browserHistory()
    const traversed = beginHybridHistoryBack(browser.target)
    const apply = vi.fn()
    const result = Promise.all([Promise.resolve('native-destination'), traversed]).then(apply)
    expect(browser.back).toHaveBeenCalledOnce()
    await Promise.resolve()
    expect(apply).not.toHaveBeenCalled()
    browser.events.dispatchEvent(new Event('popstate'))
    await result
    expect(apply).toHaveBeenCalledWith(['native-destination', undefined])
    expect(vi.getTimerCount()).toBe(0)
  })

  it('bounds cold-entry/no-op Back without requiring a browser history event', async () => {
    vi.useFakeTimers()
    const browser = browserHistory()
    const done = vi.fn()
    const result = beginHybridHistoryBack(browser.target).then(done)
    await vi.advanceTimersByTimeAsync(249)
    expect(done).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1)
    await result
    expect(done).toHaveBeenCalledOnce()
    browser.events.dispatchEvent(new Event('popstate'))
    expect(done).toHaveBeenCalledOnce()
  })

  it('cleans up and surfaces a history error without a dangling timer', async () => {
    vi.useFakeTimers()
    const browser = browserHistory(vi.fn(() => { throw new Error('history unavailable') }))
    await expect(beginHybridHistoryBack(browser.target)).rejects.toThrow('history unavailable')
    expect(vi.getTimerCount()).toBe(0)
  })
})
