import { GOOGLE_CLIENT_ID, GOOGLE_DRIVE_SCOPE } from '../config/googleDrive'
import { IS_DEVELOPMENT } from '../config/appEnvironment'

export type GoogleDriveStatus = 'disconnected' | 'connecting' | 'connected' | 'error'

export interface GoogleDriveState {
  status: GoogleDriveStatus
  email: string | null
  accountId: string | null
  errorMessage: string | null
}

interface StoredGoogleSession {
  accessToken: string
  expiresAt: number
  email: string
  accountId: string
}

interface GoogleTokenResponse {
  access_token?: string
  expires_in?: number
  error?: string
  error_description?: string
}

interface GoogleTokenClient {
  requestAccessToken(options?: { prompt?: string }): void
}

declare global {
  interface Window {
    google?: {
      accounts: {
        oauth2: {
          initTokenClient(options: {
            client_id: string
            scope: string
            callback: (response: GoogleTokenResponse) => void
            error_callback?: (error: { type?: string }) => void
          }): GoogleTokenClient
          revoke(token: string, callback?: () => void): void
        }
      }
    }
  }
}

const SESSION_KEY = 'taste-map-google-drive-session'
const listeners = new Set<() => void>()
let state: GoogleDriveState = {
  status: 'disconnected',
  email: null,
  accountId: null,
  errorMessage: null,
}
let session: StoredGoogleSession | null = restoreSession()
if (session) {
  state = { status: 'connected', email: session.email, accountId: session.accountId, errorMessage: null }
}

export function getGoogleDriveState() {
  return state
}

export function subscribeGoogleDrive(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function isGoogleDriveConnected() {
  return Boolean(validSession())
}

export async function connectGoogleDrive() {
  updateState({ status: 'connecting', errorMessage: null })
  try {
    await loadGoogleIdentityServices()
    const token = await requestGoogleToken()
    const profile = await fetchGoogleProfile(token.accessToken)
    session = {
      accessToken: token.accessToken,
      expiresAt: Date.now() + token.expiresIn * 1000 - 60_000,
      email: profile.email,
      accountId: profile.sub,
    }
    sessionStorage.setItem(SESSION_KEY, JSON.stringify(session))
    await ensureTasteMapPhotoFolder()
    updateState({ status: 'connected', email: profile.email, accountId: profile.sub, errorMessage: null })
    return state
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Google Drive 连接失败。'
    session = null
    sessionStorage.removeItem(SESSION_KEY)
    updateState({ status: 'error', email: null, accountId: null, errorMessage: message })
    throw error
  }
}

export function disconnectGoogleDrive() {
  const token = session?.accessToken
  session = null
  sessionStorage.removeItem(SESSION_KEY)
  updateState({ status: 'disconnected', email: null, accountId: null, errorMessage: null })
  if (token && window.google?.accounts.oauth2) {
    window.google.accounts.oauth2.revoke(token)
  }
}

export async function uploadGoogleDrivePhoto(photoId: string, blob: Blob) {
  const folderId = await ensureTasteMapPhotoFolder()
  const extension = blob.type === 'image/png' ? 'png' : blob.type === 'image/jpeg' ? 'jpg' : 'webp'
  const fileName = `${photoId}.${extension}`
  const boundary = `taste_map_${photoId.replace(/-/g, '')}`
  const metadata = JSON.stringify({ name: fileName, parents: [folderId] })
  const body = new Blob([
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n`,
    `--${boundary}\r\nContent-Type: ${blob.type}\r\n\r\n`,
    blob,
    `\r\n--${boundary}--`,
  ], { type: `multipart/related; boundary=${boundary}` })
  const response = await googleFetch(
    'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,mimeType,size,createdTime,modifiedTime',
    { method: 'POST', headers: { 'Content-Type': `multipart/related; boundary=${boundary}` }, body },
  )
  const payload = await response.json() as { id?: string; name?: string; size?: string }
  if (!payload.id) throw new Error('Google Drive 没有返回文件 ID。')
  return { driveFileId: payload.id, fileName: payload.name ?? fileName, fileSize: Number(payload.size ?? blob.size) }
}

export async function downloadGoogleDrivePhoto(driveFileId: string) {
  const response = await googleFetch(
    `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(driveFileId)}?alt=media`,
  )
  return response.blob()
}

export async function deleteGoogleDrivePhoto(driveFileId: string) {
  await googleFetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(driveFileId)}`, {
    method: 'DELETE',
  })
}

async function ensureTasteMapPhotoFolder() {
  const current = validSession()
  if (!current) throw new Error('请先连接 Google Drive。')
  const photoFolderName = IS_DEVELOPMENT ? 'Development Photos' : 'Photos'
  const storageKey = `taste-map-drive-folder:${current.accountId}:${photoFolderName}`
  const stored = localStorage.getItem(storageKey)
  if (stored) return stored
  const rootId = await findOrCreateFolder('Taste Map', null)
  const photoFolderId = await findOrCreateFolder(photoFolderName, rootId)
  localStorage.setItem(storageKey, photoFolderId)
  return photoFolderId
}

async function findOrCreateFolder(name: string, parentId: string | null) {
  const parentQuery = parentId ? ` and '${escapeDriveQuery(parentId)}' in parents` : " and 'root' in parents"
  const q = `name = '${escapeDriveQuery(name)}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false${parentQuery}`
  const listResponse = await googleFetch(
    `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(q)}&spaces=drive&fields=files(id,name)&pageSize=10`,
  )
  const list = await listResponse.json() as { files?: Array<{ id: string }> }
  if (list.files?.[0]?.id) return list.files[0].id
  const createResponse = await googleFetch('https://www.googleapis.com/drive/v3/files?fields=id', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      name,
      mimeType: 'application/vnd.google-apps.folder',
      ...(parentId ? { parents: [parentId] } : {}),
    }),
  })
  const created = await createResponse.json() as { id?: string }
  if (!created.id) throw new Error(`无法创建 Google Drive 文件夹“${name}”。`)
  return created.id
}

async function googleFetch(input: string, init: RequestInit = {}) {
  const current = validSession()
  if (!current) {
    updateState({ status: 'disconnected', email: null, accountId: null })
    throw new Error('Google Drive 授权已过期，请重新连接。')
  }
  const headers = new Headers(init.headers)
  headers.set('Authorization', `Bearer ${current.accessToken}`)
  const response = await fetch(input, { ...init, headers })
  if (response.ok) return response
  if (response.status === 404 && init.method === 'DELETE') return response
  const payload: unknown = await response.json().catch(() => null)
  const message = readGoogleError(payload, response.status)
  if (response.status === 401) {
    session = null
    sessionStorage.removeItem(SESSION_KEY)
    updateState({ status: 'disconnected', email: null, accountId: null, errorMessage: message })
  }
  throw new Error(message)
}

async function fetchGoogleProfile(accessToken: string) {
  const response = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!response.ok) throw new Error('无法读取当前 Google 账号。')
  const profile = await response.json() as { sub?: string; email?: string }
  if (!profile.sub || !profile.email) throw new Error('Google 账号信息不完整。')
  return { sub: profile.sub, email: profile.email }
}

function requestGoogleToken() {
  return new Promise<{ accessToken: string; expiresIn: number }>((resolve, reject) => {
    const oauth = window.google?.accounts.oauth2
    if (!oauth) {
      reject(new Error('Google 授权组件没有加载完成。'))
      return
    }
    const client = oauth.initTokenClient({
      client_id: GOOGLE_CLIENT_ID,
      scope: GOOGLE_DRIVE_SCOPE,
      callback: (response) => {
        if (response.error || !response.access_token) {
          reject(new Error(response.error_description || 'Google 授权未完成。'))
          return
        }
        resolve({ accessToken: response.access_token, expiresIn: response.expires_in ?? 3600 })
      },
      error_callback: () => reject(new Error('Google 授权窗口已关闭或被浏览器拦截。')),
    })
    client.requestAccessToken({ prompt: 'select_account consent' })
  })
}

function loadGoogleIdentityServices() {
  if (window.google?.accounts.oauth2) return Promise.resolve()
  return new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>('script[data-google-identity]')
    if (existing) {
      existing.addEventListener('load', () => resolve(), { once: true })
      existing.addEventListener('error', () => reject(new Error('Google 授权组件加载失败。')), { once: true })
      return
    }
    const script = document.createElement('script')
    script.src = 'https://accounts.google.com/gsi/client'
    script.async = true
    script.defer = true
    script.dataset.googleIdentity = 'true'
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('Google 授权组件加载失败。'))
    document.head.appendChild(script)
  })
}

function validSession() {
  if (!session || session.expiresAt <= Date.now()) return null
  return session
}

function restoreSession(): StoredGoogleSession | null {
  try {
    const raw = sessionStorage.getItem(SESSION_KEY)
    if (!raw) return null
    const value = JSON.parse(raw) as StoredGoogleSession
    return value.accessToken && value.expiresAt > Date.now() ? value : null
  } catch {
    return null
  }
}

function updateState(changes: Partial<GoogleDriveState>) {
  state = { ...state, ...changes }
  listeners.forEach((listener) => listener())
}

function escapeDriveQuery(value: string) {
  return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
}

function readGoogleError(value: unknown, status: number) {
  const record = value && typeof value === 'object' ? value as Record<string, unknown> : null
  const error = record?.error && typeof record.error === 'object' ? record.error as Record<string, unknown> : null
  const message = typeof error?.message === 'string' ? error.message : `Google Drive 请求失败（${status}）`
  return /storageQuotaExceeded|quota/i.test(JSON.stringify(value))
    ? 'Google Drive 空间不足，照片仍保存在本机但尚未同步。'
    : message
}
