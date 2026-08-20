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
