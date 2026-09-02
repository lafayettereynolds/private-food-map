import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readdir, readFile, stat } from 'node:fs/promises'
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
  'authorizationCode',
  'refreshToken',
  '__TASTEMAP_UI_TEST_RUNTIME',
  'api-dev.tastemap.cn',
  'BEGIN PRIVATE KEY',
  '/Users/lafayette',
]

for (const marker of forbiddenMarkers) {
  assert.equal(releaseText.includes(marker), false, `Release App contains forbidden test/development marker: ${marker}`)
}

const bundledConfig = JSON.parse(await readFile(resolve(appPath, 'capacitor.config.json'), 'utf8'))
assert.equal(bundledConfig.server?.url, undefined, 'Release App must load its UI from the signed local bundle.')
assert.equal(entries.some((path) => path.includes('/_hybrid_debug/')), false, 'Debug fixture directory entered Release App.')

console.log(`Hybrid Release purity scan passed: ${entries.length} files, no test fixture, debug route, test auth, development URL, secret, or remote server.url markers.`)

async function filesIn(directory) {
  const values = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name)
    if (entry.isDirectory()) values.push(...await filesIn(path))
    else if (entry.isFile()) values.push(path)
  }
  return values
}
