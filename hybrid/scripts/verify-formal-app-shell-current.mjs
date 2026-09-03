import { createHash } from 'node:crypto'
import { readdir, readFile, stat } from 'node:fs/promises'
import { relative, resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const dist = resolve(root, 'dist')
const staged = resolve(root, 'ios/TasteMap/HybridRuntimeResources/public')

async function inventory(directory) {
  const files = new Map()

  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const absolute = resolve(current, entry.name)
      if (entry.isDirectory()) {
        await visit(absolute)
      } else if (entry.isFile()) {
        const contents = await readFile(absolute)
        files.set(relative(directory, absolute), createHash('sha256').update(contents).digest('hex'))
      }
    }
  }

  await visit(directory)
  return files
}

async function compareDirectories(expectedDirectory, actualDirectory, label) {
  const [expected, actual] = await Promise.all([
    inventory(expectedDirectory),
    inventory(actualDirectory),
  ])

  const missing = [...expected.keys()].filter((path) => !actual.has(path))
  const unexpected = [...actual.keys()].filter((path) => !expected.has(path))
  const changed = [...expected.keys()].filter((path) => actual.has(path) && expected.get(path) !== actual.get(path))

  if (missing.length || unexpected.length || changed.length) {
    const describe = (name, paths) => paths.length ? `\n${name}:\n  ${paths.join('\n  ')}` : ''
    throw new Error(
      `${label} is stale or does not match its source.`
      + describe('Missing', missing)
      + describe('Unexpected', unexpected)
      + describe('Changed', changed),
    )
  }

  console.log(`PASS ${label}: ${expected.size} files match byte-for-byte.`)
}

async function assertFormalIndex(directory, label) {
  const index = await readFile(resolve(directory, 'index.html'), 'utf8')
  const forbidden = ['_hybrid_debug', 'api-dev.tastemap.cn']
  const leaked = forbidden.filter((token) => index.includes(token))
  if (leaked.length) {
    throw new Error(`${label} contains forbidden Debug/Development references: ${leaked.join(', ')}`)
  }

  const assetReferences = [...index.matchAll(/(?:src|href)="\/([^"?#]+)["?#]?/g)].map((match) => match[1])
  if (!assetReferences.length) throw new Error(`${label} does not reference any local assets.`)

  for (const asset of assetReferences) {
    const metadata = await stat(resolve(directory, asset))
    if (!metadata.isFile()) throw new Error(`${label} references a non-file asset: ${asset}`)
  }
}

await compareDirectories(dist, staged, 'formal staged Hybrid resources')
await assertFormalIndex(staged, 'formal staged Hybrid index')

const builtAppArgument = process.argv.slice(2).find((argument) => argument !== '--')
if (builtAppArgument) {
  const builtApp = resolve(builtAppArgument)
  const builtPublic = resolve(builtApp, 'public')
  await compareDirectories(staged, builtPublic, 'built TasteMap.app Hybrid resources')
  await assertFormalIndex(builtPublic, 'built TasteMap.app Hybrid index')
} else {
  console.log('No built .app path supplied; staged-resource verification complete.')
}
