import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { PublicRestaurantPage } from './components/PublicRestaurantPage'
import './styles/global.css'

const publicRestaurantMatch = window.location.pathname.match(/^\/restaurant\/([a-f0-9]{24})\/?$/)

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {publicRestaurantMatch ? <PublicRestaurantPage publicRestaurantId={publicRestaurantMatch[1]} /> : <App />}
  </React.StrictMode>,
)
