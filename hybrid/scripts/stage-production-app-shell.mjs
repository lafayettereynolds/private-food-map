import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const source = resolve(root, 'dist')
const resources = resolve(root, 'ios/TasteMap/HybridRuntimeResources')
const destination = resolve(resources, 'public')

await rm(destination, { recursive: true, force: true })
await mkdir(resources, { recursive: true })
await cp(source, destination, { recursive: true })

const indexPath = resolve(destination, 'index.html')
const index = await readFile(indexPath, 'utf8')
if (index.includes('_hybrid_debug') || index.includes('api-dev.tastemap.cn')) {
  throw new Error('Refusing to stage a Debug or Development Hybrid bundle in the formal app.')
}

const manifest = {
  schemaVersion: 1,
  source: 'vite-hybrid-release',
  localBundle: true,
  stagedAtBuildTime: false,
}
await writeFile(resolve(resources, 'hybrid-bundle-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
console.log(`Staged signed Hybrid UI resources at ${destination}`)
