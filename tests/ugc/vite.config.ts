import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
// Isolated UI harness: no proxy, no remote APIs and no Production asset staging.
export default defineConfig({
  plugins: [react()], publicDir: false,
  server: { host: '127.0.0.1', port: 5197, strictPort: true, watch: { ignored: ['**/.private/**'] } },
})
