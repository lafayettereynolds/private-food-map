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

export const DATABASE_NAME = IS_DEVELOPMENT ? 'food-map-dev' : 'food-map-prod'

export const ENVIRONMENT_LABEL = IS_DEVELOPMENT ? '测试环境' : '正式环境'

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
