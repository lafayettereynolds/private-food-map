import assert from 'node:assert/strict'
import { access, readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const config = JSON.parse(await readFile(resolve(root, 'hybrid-poc/capacitor-shell/capacitor.config.json'), 'utf8'))

assert.equal(config.webDir, '../../dist')
assert.equal(config.server?.url, undefined, 'A remote server URL would invalidate the local-bundle POC.')
assert.equal(config.appId, 'com.lafayette.tastemap.hybridpoc')
await access(resolve(root, 'dist/index.html'))
await access(resolve(root, 'dist/hybrid-poc/dataset.json'))

const appDelegate = await readFile(resolve(root, 'hybrid-poc/capacitor-shell/ios/App/App/AppDelegate.swift'), 'utf8')
for (const method of ['runtimeInfo', 'profileGetCurrent', 'restaurantGet', 'hapticsSelection', 'authSessionStatus', 'authSignInWithApple']) {
  assert.match(appDelegate, new RegExp(`CAPPluginMethod\\(name: "${method}"`))
}
assert.doesNotMatch(appDelegate, /identityToken|authorizationCode|accessToken|refreshToken/)

const pocApp = await readFile(resolve(root, 'src/hybrid-poc/HybridPOCApp.tsx'), 'utf8')
assert.match(pocApp, /remoteStatsEnabled=\{false\}/, 'The shared detail body must not start a backend request in the local POC.')

console.log('Capacitor POC local-bundle and bridge-shape verification passed.')
