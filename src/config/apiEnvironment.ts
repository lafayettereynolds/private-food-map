import { APP_ENVIRONMENT, type AppEnvironment } from './appEnvironment'

interface APIEnvironmentValues {
  VITE_API_BASE_URL?: string
  VITE_API_DEV_BASE_URL?: string
  VITE_API_PROD_BASE_URL?: string
}

export function resolveAPIBaseURL(environment: AppEnvironment, values: APIEnvironmentValues) {
  const configured = (
    environment === 'development' ? values.VITE_API_DEV_BASE_URL : values.VITE_API_PROD_BASE_URL
  )?.trim() || values.VITE_API_BASE_URL?.trim() || ''
  if (!configured) return null

  let url: URL
  try {
    url = new URL(configured)
  } catch {
    throw new Error(`Taste Map ${environment} API Base URL 不是有效 URL。`)
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
    throw new Error(`Taste Map ${environment} API Base URL 只能是无凭据、无 query/hash 的 HTTP(S) 地址。`)
  }
  return url.toString().replace(/\/$/, '')
}

export const API_BASE_URL = resolveAPIBaseURL(APP_ENVIRONMENT, import.meta.env)

export function apiURL(path: string, baseURL: string | null = API_BASE_URL) {
  if (!path.startsWith('/')) throw new Error('Taste Map API path 必须以 / 开头。')
  return baseURL ? new URL(path, `${baseURL}/`).toString() : path
}
