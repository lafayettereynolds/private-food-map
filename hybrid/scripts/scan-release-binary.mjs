import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { access, readdir, readFile, stat } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const appPath = resolve(process.argv[2] ?? resolve(root, 'build/hybrid-derived-data/Build/Products/Release-iphonesimulator/App.app'))
const entries = await filesIn(appPath)
const text = []

for (const path of entries) {
  const info = await stat(path)
  if (info.size > 80_000_000) continue
  if (/\.(?:html|js|css|json|plist|xml|txt|strings|entitlements)$/i.test(path)) {
    text.push(await readFile(path, 'utf8'))
    continue
  }
  try {
    text.push(execFileSync('/usr/bin/strings', ['-a', path], { encoding: 'utf8', maxBuffer: 80_000_000 }))
  } catch {
    // Non-readable resource formats are irrelevant to the string purity scan.
  }
}

const releaseText = text.join('\n')
const forbiddenMarkers = [
  '_hybrid_debug',
  'profile-restaurant-rich.json',
  'tm_hybrid_debug',
  'native-swiftdata-debug-fixture',
  'TasteMapHybridDebugFixture',
  'VITE_HYBRID_DEBUG_ROUTE',
  'X-Taste-Map-Test-User',
  '__TASTEMAP_UI_TEST_RUNTIME',
  'api-dev.tastemap.cn',
  'BEGIN PRIVATE KEY',
  '/Users/lafayette',
  '--tastemap-hybrid-development',
  'TASTEMAP_VISUAL_QA_MODE',
]

for (const marker of forbiddenMarkers) {
  assert.equal(releaseText.includes(marker), false, `Release App contains forbidden test/development marker: ${marker}`)
}

// Native AuthSessionManager must retain its Keychain-backed credential model.
// The Release security boundary is that credential vocabulary never enters
// the signed React bundle or bridge DTO surface.
const publicRoot = resolve(appPath, 'public')
const webEntries = await filesIn(publicRoot)
const webText = []
const signedWebPaths = [...webEntries, resolve(appPath, 'capacitor.config.json')]
const optionalFormalManifest = resolve(appPath, 'hybrid-bundle-manifest.json')
try {
  await access(optionalFormalManifest)
  signedWebPaths.push(optionalFormalManifest)
} catch {
  // The internal Capacitor validation shell does not embed the formal-app
  // resource manifest. The shipping TasteMap target does, and is scanned by
  // scan-formal-release-app.mjs. Both targets still scan their complete signed
  // local Web payload and fail closed on Debug/development/credential markers.
}
for (const path of signedWebPaths) {
  webText.push(await readFile(path, 'utf8'))
}
const signedWebText = webText.join('\n')
for (const marker of [
  'accessToken',
  'refreshToken',
  'identityToken',
  'authorizationCode',
  'Authorization',
  'Bearer ',
]) {
  assert.equal(signedWebText.includes(marker), false, `Formal Hybrid Web bundle exposes credential marker: ${marker}`)
}

const bundledConfig = JSON.parse(await readFile(resolve(appPath, 'capacitor.config.json'), 'utf8'))
assert.equal(bundledConfig.server?.url, undefined, 'Release App must load its UI from the signed local bundle.')
assert.equal(entries.some((path) => path.includes('/_hybrid_debug/')), false, 'Debug fixture directory entered Release App.')

console.log(`Hybrid Release purity scan passed: ${entries.length} app files, ${webEntries.length} signed Web files; no test fixture, debug route, test auth, development URL, secret, remote server.url, or React credential markers.`)

async function filesIn(directory) {
  const values = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name)
    if (entry.isDirectory()) values.push(...await filesIn(path))
    else if (entry.isFile()) values.push(path)
  }
  return values
}
