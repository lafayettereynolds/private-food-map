/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_APP_ENV?: 'development' | 'production'
  readonly VITE_HYBRID_SHELL?: 'true' | 'false'
  readonly VITE_HYBRID_INTERNAL?: 'true' | 'false'
  readonly VITE_HYBRID_DEBUG_ROUTE?: string
  readonly VITE_CLOUD_SYNC_ENABLED?: 'true' | 'false'
  readonly VITE_SOCIAL_API_ENABLED?: 'true' | 'false'
  readonly VITE_API_BASE_URL?: string
  readonly VITE_API_DEV_BASE_URL?: string
  readonly VITE_API_PROD_BASE_URL?: string
  readonly VITE_AMAP_KEY?: string
  readonly VITE_AMAP_SECURITY_CODE?: string
  readonly VITE_AMAP_SECURITY_KEY?: string
  readonly VITE_AMAP_DEV_KEY?: string
  readonly VITE_AMAP_DEV_SECURITY_CODE?: string
  readonly VITE_AMAP_DEV_SECURITY_KEY?: string
  readonly VITE_AMAP_PROD_KEY?: string
  readonly VITE_AMAP_PROD_SECURITY_CODE?: string
  readonly VITE_AMAP_PROD_SECURITY_KEY?: string
  readonly VITE_GOOGLE_CLIENT_ID?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
