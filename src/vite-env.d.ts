/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_APP_ENV?: 'development' | 'production'
  readonly VITE_AMAP_KEY?: string
  readonly VITE_AMAP_SECURITY_CODE?: string
  readonly VITE_AMAP_DEV_KEY?: string
  readonly VITE_AMAP_DEV_SECURITY_CODE?: string
  readonly VITE_AMAP_PROD_KEY?: string
  readonly VITE_AMAP_PROD_SECURITY_CODE?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
