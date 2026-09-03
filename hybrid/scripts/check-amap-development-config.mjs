import { resolve } from 'node:path'
import { loadEnv } from 'vite'

const root = resolve(import.meta.dirname, '../..')
const environment = loadEnv('hybrid-debug', root, '')

const keyConfigured = hasValue(environment.VITE_AMAP_DEV_KEY)
const securityConfigured = hasValue(
  environment.VITE_AMAP_DEV_SECURITY_CODE || environment.VITE_AMAP_DEV_SECURITY_KEY,
)

console.log('Taste Map Browser Development AMap readiness (values are never printed)')
console.log('This check applies only to the Browser Web map provider. iOS Hybrid uses Native MapKit.')
console.log(`VITE_AMAP_DEV_KEY: ${keyConfigured ? 'CONFIGURED' : 'MISSING'}`)
console.log(`VITE_AMAP_DEV_SECURITY_CODE/KEY: ${securityConfigured ? 'CONFIGURED' : 'MISSING'}`)

if (!keyConfigured || !securityConfigured) {
  console.error('BROWSER AMAP DEVELOPMENT PREVIEW = BLOCKED BY DEVELOPMENT AMAP CREDENTIAL')
  console.error('Put the Development-only values in .env.hybrid-debug.local; never commit that file.')
  process.exitCode = 2
} else {
  console.log('DEVELOPMENT AMAP CONFIG = READY FOR LIVE RUNTIME VALIDATION')
  console.log('This check does not claim Browser pan/pinch PASS. It is unrelated to iOS MapKit acceptance.')
}

function hasValue(value) {
  return typeof value === 'string' && value.trim().length > 0
}
