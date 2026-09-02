import React from 'react'
import ReactDOM from 'react-dom/client'
import { HybridAppShell } from './app/HybridAppShell'
import '../styles/global.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <HybridAppShell />
  </React.StrictMode>,
)
