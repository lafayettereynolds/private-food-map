import { access, cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const source = resolve(root, 'dist')
const resources = resolve(root, 'ios/TasteMap/HybridRuntimeResources')
const destination = resolve(resources, 'public')

// This script is deliberately Debug-only. It refuses to stage a bundle that
// does not contain the deterministic fixture installed by hybrid:build:debug.
await access(resolve(source, '_hybrid_debug/profile-restaurant-rich.json'))
const index = await readFile(resolve(source, 'index.html'), 'utf8')
if (index.includes('api-dev.tastemap.cn')) {
  throw new Error('The internal Hybrid UI must remain local and cannot embed a Development API origin.')
}

await rm(destination, { recursive: true, force: true })
await mkdir(resources, { recursive: true })
await cp(source, destination, { recursive: true })
await writeFile(resolve(resources, 'hybrid-bundle-manifest.json'), `${JSON.stringify({
  schemaVersion: 1,
  source: 'vite-hybrid-debug',
  localBundle: true,
  stagedAtBuildTime: false,
}, null, 2)}\n`)

console.log(`Staged internal Debug Hybrid UI resources at ${destination}`)
