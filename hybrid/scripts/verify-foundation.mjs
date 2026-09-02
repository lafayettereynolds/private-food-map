import assert from 'node:assert/strict'
import { access, readFile, readdir, stat } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const release = process.argv.includes('--release')
const debug = process.argv.includes('--debug')
assert.notEqual(release, debug, 'Choose exactly one verification mode.')

const config = JSON.parse(await readFile(resolve(root, 'hybrid/capacitor-shell/capacitor.config.json'), 'utf8'))
assert.equal(config.webDir, '../../dist')
assert.equal(config.server?.url, undefined, 'Release and Debug bundles must not depend on a remote UI server.')
assert.equal(config.appId, 'com.lafayette.tastemap.hybrid.internal')
assert.equal(config.loggingBehavior, 'none')
await access(resolve(root, 'dist/index.html'))

const fixturePath = resolve(root, 'dist/_hybrid_debug/profile-restaurant-rich.json')
if (debug) await access(fixturePath)
if (release) await assert.rejects(access(fixturePath), 'A Debug fixture entered the Release Web bundle.')

const appDelegate = await readFile(resolve(root, 'hybrid/capacitor-shell/ios/App/App/AppDelegate.swift'), 'utf8')
assert.match(appDelegate, /CAPPluginMethod\(name: "invoke"/)
assert.match(appDelegate, /#if DEBUG[\s\S]*TasteMapHybridDebugFixture/)
assert.doesNotMatch(appDelegate, /server\.url/)

const packageManifest = await readFile(resolve(root, 'hybrid/capacitor-shell/ios/App/CapApp-SPM/Package.swift'), 'utf8')
assert.match(packageManifest, /TasteMapHybridBridge/)
assert.match(packageManifest, /TasteMapRepository/)

const bundleText = await readTextTree(resolve(root, 'dist'))
for (const forbidden of release ? [
  'tm_capacitor_poc', 'local-poc', 'hybridPOC', 'profile-restaurant-rich.json',
  'X-Taste-Map-Test-User', 'identityToken', 'authorizationCode', 'refreshToken',
  'accessToken', 'Authorization', 'Bearer ',
  '/Users/lafayette/', 'BEGIN PRIVATE KEY',
] : ['tm_capacitor_poc', 'local-poc', 'hybridPOC', '/Users/lafayette/', 'BEGIN PRIVATE KEY']) {
  assert.equal(bundleText.includes(forbidden), false, `Forbidden Hybrid bundle marker: ${forbidden}`)
}

async function readTextTree(directory) {
  const values = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name)
    if (entry.isDirectory()) values.push(await readTextTree(path))
    else if (/\.(?:html|js|css|json|txt|map)$/.test(entry.name) && (await stat(path)).size < 20_000_000) values.push(await readFile(path, 'utf8'))
  }
  return values.join('\n')
}

console.log(`Hybrid Foundation ${release ? 'Release' : 'Debug'} local-bundle verification passed.`)
