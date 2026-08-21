export const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID ||
  '289252662026-79e3ri4gh59ldgi5lqrk2govv3g7ev9f.apps.googleusercontent.com'

export const GOOGLE_DRIVE_SCOPE = [
  'openid',
  'email',
  'https://www.googleapis.com/auth/drive.file',
].join(' ')
