import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'

export const PremiumAccessContext = createContext<boolean | null>(null)
export const PremiumAccountContext = createContext('guest')
export function usePremiumAccess() { return useContext(PremiumAccessContext) === true }
export function useResolvedPremiumAccess() { return useContext(PremiumAccessContext) }

/** Only the host's entitlement service grants access; unresolved reads fail closed. */
export function PremiumAccessBoundary({ platform, revision, ownerID, children }: { platform: TasteMapPlatform; revision: string; ownerID: string; children: ReactNode }) {
  const [allowed, setAllowed] = useState<boolean | null>(null)
  useEffect(() => {
    let current = true
    setAllowed(null)
    void platform.premium.status().then(status => { if (current) setAllowed(status.state === 'premium') }).catch(() => { if (current) setAllowed(false) })
    return () => { current = false }
  }, [platform, revision])
  return <PremiumAccountContext.Provider value={ownerID}><PremiumAccessContext.Provider value={allowed}>{children}</PremiumAccessContext.Provider></PremiumAccountContext.Provider>
}
