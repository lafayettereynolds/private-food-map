import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const repositoryRoot = fileURLToPath(new URL('.', import.meta.url))

export default defineConfig(({ mode }) => {
  const isHybridBundle = mode === 'hybrid' || mode === 'hybrid-debug'
  const browserPhotoAssets = fileURLToPath(new URL('./src/services/photoAssets.ts', import.meta.url))
  const hybridPhotoAssets = fileURLToPath(new URL('./src/hybrid/platform/HybridPhotoAssets.ts', import.meta.url))
  return {
    root: isHybridBundle ? fileURLToPath(new URL('./hybrid/app/', import.meta.url)) : repositoryRoot,
    publicDir: fileURLToPath(new URL('./public/', import.meta.url)),
    plugins: [
      isHybridBundle ? {
        name: 'tastemap-hybrid-photo-assets',
        enforce: 'pre' as const,
        async resolveId(source: string, importer: string | undefined, options: { attributes?: Record<string, string> }) {
          if (!importer) return null
          const resolved = await this.resolve(source, importer, { ...options, skipSelf: true })
          return resolved?.id.split('?')[0] === browserPhotoAssets ? hybridPhotoAssets : null
        },
      } : null,
      react(),
    ].filter(Boolean),
    build: isHybridBundle ? {
      outDir: fileURLToPath(new URL('./dist/', import.meta.url)),
      emptyOutDir: true,
    } : undefined,
    server: {
      proxy: {
        '/api': {
          target: 'http://127.0.0.1:8788',
          changeOrigin: true,
        },
      },
    },
  }
})
