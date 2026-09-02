import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { loadEnv } from 'vite'

const root = resolve(import.meta.dirname, '../..')
const environment = loadEnv('hybrid-debug', root, '')
const shellConfig = JSON.parse(await readFile(resolve(root, 'hybrid/capacitor-shell/capacitor.config.json'), 'utf8'))

const keyConfigured = hasValue(environment.VITE_AMAP_DEV_KEY)
const securityConfigured = hasValue(
  environment.VITE_AMAP_DEV_SECURITY_CODE || environment.VITE_AMAP_DEV_SECURITY_KEY,
)
const scheme = shellConfig.server?.iosScheme || 'capacitor'
const hostname = shellConfig.server?.hostname || 'localhost'

console.log('Taste Map Development AMap readiness (values are never printed)')
console.log(`Capacitor local origin: ${scheme}://${hostname}`)
console.log(`VITE_AMAP_DEV_KEY: ${keyConfigured ? 'CONFIGURED' : 'MISSING'}`)
console.log(`VITE_AMAP_DEV_SECURITY_CODE/KEY: ${securityConfigured ? 'CONFIGURED' : 'MISSING'}`)

if (!keyConfigured || !securityConfigured) {
  console.error('REAL AMAP INTERACTION = BLOCKED BY DEVELOPMENT AMAP CREDENTIAL')
  console.error('Put the Development-only values in .env.hybrid-debug.local; never commit that file.')
  process.exitCode = 2
} else {
  console.log('DEVELOPMENT AMAP CONFIG = READY FOR LIVE RUNTIME VALIDATION')
  console.log('This check does not claim pan/pinch PASS; the fixed-Simulator gesture run is still required.')
}

function hasValue(value) {
  return typeof value === 'string' && value.trim().length > 0
}
