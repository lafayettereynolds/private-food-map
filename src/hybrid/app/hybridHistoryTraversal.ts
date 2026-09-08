/** Start visible Back immediately, but do not let an early Native reply race a later popstate. */
export function beginHybridHistoryBack(target: Pick<Window, 'history' | 'addEventListener' | 'removeEventListener'> = window, timeoutMS = 250): Promise<void> {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timer)
      target.removeEventListener('popstate', finish)
    }
    const finish = () => { cleanup(); resolve() }
    // No previous Web entry (for example a cold Native destination) emits no
    // popstate. Bound the wait so Native's authoritative result still arrives.
    const timer = setTimeout(finish, timeoutMS)
    target.addEventListener('popstate', finish, { once: true })
    try { target.history.back() } catch (error) { cleanup(); reject(error) }
  })
}
