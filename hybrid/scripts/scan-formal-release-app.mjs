import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFile, readdir, stat } from 'node:fs/promises'
import { resolve } from 'node:path'

const repositoryRoot = resolve(import.meta.dirname, '../..')
const internal = process.argv.includes('--internal')
const requestedPath = process.argv.slice(2).find((value) => !value.startsWith('--'))
const appPath = resolve(requestedPath ?? resolve(
  repositoryRoot,
  'build/phase2a-derived-data/Build/Products/Release-iphoneos/TasteMap.app',
))
const allFiles = await filesIn(appPath)
const wholeAppText = await readableText(allFiles)
const plist = JSON.parse(execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', resolve(appPath, 'Info.plist')], { encoding: 'utf8' }))
if (internal) {
  assert.equal(plist.TasteMapDistributionChannel, 'internal')
  assert.equal(plist.TasteMapExpectedAPIBaseURL, 'https://api-dev.tastemap.cn')
  assert.equal(plist.CFBundleIdentifier, 'com.lafayette.tastemap')
  assert.equal(wholeAppText.includes('HYBRID_PRIMARY'), true)
} else {
  assert.notEqual(plist.TasteMapDistributionChannel, 'internal', 'Use the explicit Internal audit for an Internal artifact.')
}
const publicRoot = resolve(appPath, 'public')
const webFiles = await filesIn(publicRoot)
const webText = await readableText([
  ...webFiles,
  resolve(appPath, 'capacitor.config.json'),
  resolve(appPath, 'hybrid-bundle-manifest.json'),
])

for (const marker of [
  'PhotoDeleteQASessionFixture',
  'PhotoDeleteQASessionBootstrap',
  'PhotoDeleteQATestService',
  'TASTEMAP_PHOTO_DELETE_QA_SESSION',
  'TASTEMAP_PHOTO_DELETE_QA_RUN',
  'photo-delete.qa.invalid',
  'photo-qa-access-',
  'photo-qa-refresh-',
  'qa-photo-owner',
  'qa-photo-other-user',
  'tm_qa_photo_other_user',
  'photo-delete-qa-local-identity',
  '_hybrid_debug',
  'profile-restaurant-rich.json',
  'tm_hybrid_debug',
  'native-swiftdata-debug-fixture',
  'TasteMapHybridDebugFixture',
  'VITE_HYBRID_DEBUG_ROUTE',
  'X-Taste-Map-Test-User',
  '__TASTEMAP_UI_TEST_RUNTIME',
  ...(internal ? [] : ['api-dev.tastemap.cn']),
  'TasteMapSandboxAPIBaseURL',
  'premium-sandbox-catalog',
  'BEGIN PRIVATE KEY',
  '/Users/lafayette',
  '--tastemap-hybrid-development',
  'TASTEMAP_VISUAL_QA_MODE',
  'TASTEMAP_MAP_FRAME_DIAGNOSTICS',
  'TASTEMAP_MAP_FRAME_SAMPLE',
  'TASTEMAP_MAP_CAMERA_TRACE',
  'TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST',
  'TASTEMAP_LOCATION_DIAGNOSTICS',
  'TasteMapLocationTrace',
  'DevelopmentPremiumOverride',
  'TASTEMAP_SIGNUP_TRIAL_UI_TEST',
  'tm_signup_trial_ui_fixture',
  'SignupTrialUITestAPI',
  'TASTEMAP_REFERRAL_UI_TEST',
  'referral-qa-pending',
  'setDevelopmentOverride',
  'activateVisualQAFixture',
  'tm_access_local_admin_smoke_not_a_real_account',
  '/internal/premium',
  '/api/v1/admin/memberships',
]) {
  assert.equal(wholeAppText.includes(marker), false, `Formal Release App contains forbidden test/development marker: ${marker}`)
}

// Native AuthSessionManager must retain its credential implementation. The
// security boundary is that none of those credentials enter the React bundle
// or its bridge DTOs, so token markers are checked specifically in public/.
for (const marker of [
  'accessToken',
  'refreshToken',
  'identityToken',
  'authorizationCode',
  'Authorization',
  'Bearer ',
]) {
  assert.equal(webText.includes(marker), false, `Formal Hybrid Web bundle exposes credential marker: ${marker}`)
}

const capacitorConfig = JSON.parse(await readFile(resolve(appPath, 'capacitor.config.json'), 'utf8'))
assert.equal(capacitorConfig.server?.url, undefined, 'Formal Release must load its UI from the signed local bundle.')
assert.equal(capacitorConfig.webDir, 'public')
assert.equal(capacitorConfig.ios?.webContentsDebuggingEnabled, false)
assert.equal(allFiles.some((path) => path.includes('/_hybrid_debug/')), false)

const bundleManifest = JSON.parse(await readFile(resolve(appPath, 'hybrid-bundle-manifest.json'), 'utf8'))
assert.equal(bundleManifest.localBundle, true)
assert.equal(bundleManifest.source, 'vite-hybrid-release')

console.log(
  `Formal Hybrid Release purity scan passed: ${allFiles.length} app files, ${webFiles.length} signed Web files; `
  + `no Debug switch/fixture/local path/secret and no credential surface in React; channel=${internal ? 'Internal (approved Development API)' : 'Production (no Development URL)'}.`,
)

async function readableText(paths) {
  const values = []
  for (const path of paths) {
    const info = await stat(path)
    if (info.size > 80_000_000) continue
    if (/\.(?:html|js|css|json|plist|xml|txt|strings|entitlements|xcprivacy)$/i.test(path)) {
      values.push(await readFile(path, 'utf8'))
      continue
    }
    try {
      values.push(execFileSync('/usr/bin/strings', ['-a', path], { encoding: 'utf8', maxBuffer: 80_000_000 }))
    } catch {
      // Opaque resources are outside the text-scan surface.
    }
  }
  return values.join('\n')
}

async function filesIn(directory) {
  const values = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name)
    if (entry.isDirectory()) values.push(...await filesIn(path))
    else if (entry.isFile()) values.push(path)
  }
  return values
}
