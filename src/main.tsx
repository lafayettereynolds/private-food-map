import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { PublicRestaurantPage } from './components/PublicRestaurantPage'
import { PublicSharePage } from './components/PublicSharePage'
import { HybridPOCApp } from './hybrid-poc/HybridPOCApp'
import { shouldRenderHybridPOC } from './platform/tasteMapPlatformResolver'
import './styles/global.css'

const publicRestaurantMatch = window.location.pathname.match(/^\/restaurant\/([a-f0-9]{24})\/?$/)
const publicShareMatch = window.location.pathname.match(/^\/share\/([A-Za-z0-9_-]{32})\/?$/)
const hybridPOC = shouldRenderHybridPOC()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {hybridPOC
      ? <HybridPOCApp />
      : publicShareMatch
      ? <PublicSharePage shareId={publicShareMatch[1]} />
      : publicRestaurantMatch
        ? <PublicRestaurantPage publicRestaurantId={publicRestaurantMatch[1]} />
        : <App />}
  </React.StrictMode>,
)
