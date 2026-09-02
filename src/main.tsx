import React, { lazy, Suspense } from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { PublicRestaurantPage } from './components/PublicRestaurantPage'
import { PublicSharePage } from './components/PublicSharePage'
import { shouldRenderHybridShell } from './platform/tasteMapPlatformResolver'
import './styles/global.css'

const publicRestaurantMatch = window.location.pathname.match(/^\/restaurant\/([a-f0-9]{24})\/?$/)
const publicShareMatch = window.location.pathname.match(/^\/share\/([A-Za-z0-9_-]{32})\/?$/)
const hybridShell = shouldRenderHybridShell()
const HybridAppShell = lazy(async () => ({
  default: (await import('./hybrid/app/HybridAppShell')).HybridAppShell,
}))

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {hybridShell
      ? <Suspense fallback={<main aria-live="polite">正在启动 Taste Map…</main>}><HybridAppShell /></Suspense>
      : publicShareMatch
      ? <PublicSharePage shareId={publicShareMatch[1]} />
      : publicRestaurantMatch
        ? <PublicRestaurantPage publicRestaurantId={publicRestaurantMatch[1]} />
        : <App />}
  </React.StrictMode>,
)
