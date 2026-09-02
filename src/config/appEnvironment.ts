export type AppEnvironment = 'development' | 'production'

const requestedEnvironment = import.meta.env.VITE_APP_ENV?.trim().toLowerCase()

export const APP_ENVIRONMENT: AppEnvironment = requestedEnvironment === 'production'
  ? 'production'
  : requestedEnvironment === 'development'
    ? 'development'
    : import.meta.env.PROD
      ? 'production'
      : 'development'

export const IS_DEVELOPMENT = APP_ENVIRONMENT === 'development'

export type LocalTestAccount = 'premium' | 'free'

const requestedTestAccount = typeof window !== 'undefined'
  ? new URLSearchParams(window.location.search).get('testAccount')
  : null

export const LOCAL_TEST_ACCOUNT: LocalTestAccount = IS_DEVELOPMENT && requestedTestAccount === 'free'
  ? 'free'
  : 'premium'

export const LOCAL_TEST_VIEWER_ID = LOCAL_TEST_ACCOUNT === 'free' ? 'free-tester' : 'owner'

// The free test account deliberately uses a different IndexedDB. This keeps the
// owner's long-lived development data intact while allowing strict free-tier QA.
export const DATABASE_NAME = IS_DEVELOPMENT
  ? LOCAL_TEST_ACCOUNT === 'free' ? 'food-map-dev-free' : 'food-map-dev'
  : 'food-map-prod'

export const ENVIRONMENT_LABEL = IS_DEVELOPMENT ? '测试环境' : '正式环境'

export function localTestHeaders(): Record<string, string> {
  // Keep the test-auth header out of production bundles entirely. Vite folds
  // this build-time branch for Release instead of retaining a dormant runtime
  // implementation in the Capacitor local Web assets.
  if (import.meta.env.VITE_APP_ENV !== 'development') return {}
  return { 'X-Taste-Map-Test-User': LOCAL_TEST_VIEWER_ID }
}

export const BACKUP_FILE_PREFIX = IS_DEVELOPMENT
  ? 'food-map-dev-backup'
  : 'food-map-backup'

const explicitlyEnabledCloudSync = import.meta.env.VITE_CLOUD_SYNC_ENABLED === 'true'
const explicitlyDisabledCloudSync = import.meta.env.VITE_CLOUD_SYNC_ENABLED === 'false'
const explicitlyEnabledSocialApi = import.meta.env.VITE_SOCIAL_API_ENABLED === 'true'
const explicitlyDisabledSocialApi = import.meta.env.VITE_SOCIAL_API_ENABLED === 'false'
const isSecureHostedApp = typeof window !== 'undefined' && window.location.protocol === 'https:'
const isLocalDevelopmentApp = typeof window !== 'undefined' && IS_DEVELOPMENT && (
  window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
)

export const CLOUD_SYNC_ENABLED = !explicitlyDisabledCloudSync && (
  !IS_DEVELOPMENT && (explicitlyEnabledCloudSync || isSecureHostedApp)
)

// Social discovery is a read-oriented channel. Local development may use it to
// preview follows, community feeds and aggregate ratings without enabling the
// personal IndexedDB <-> D1 synchronization channel above.
export const SOCIAL_API_ENABLED = !explicitlyDisabledSocialApi && (
  explicitlyEnabledSocialApi || isLocalDevelopmentApp || (!IS_DEVELOPMENT && isSecureHostedApp)
)
