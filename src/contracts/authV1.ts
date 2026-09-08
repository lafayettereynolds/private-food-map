export const AUTH_API_VERSION = 1 as const

export interface AuthChallengeResponseV1 {
  apiVersion: typeof AUTH_API_VERSION
  state: string
  nonce: string
  expiresAt: string
}

export interface AppleTokenExchangeRequestV1 {
  apiVersion: typeof AUTH_API_VERSION
  identityToken: string
  state: string
  nonce: string
  givenName?: string | null
  familyName?: string | null
  referralCode?: string | null
}

export interface AuthUserV1 {
  id: string
  email: string | null
}

export interface AuthSessionV1 {
  accessToken: string
  accessTokenExpiresAt: string
  refreshToken: string
  refreshTokenExpiresAt: string
}

export interface AuthSessionResponseV1 {
  apiVersion: typeof AUTH_API_VERSION
  user: AuthUserV1
  session: AuthSessionV1
}

export interface RefreshSessionRequestV1 {
  apiVersion: typeof AUTH_API_VERSION
  refreshToken: string
}

export interface LogoutRequestV1 {
  apiVersion: typeof AUTH_API_VERSION
  refreshToken?: string
}
