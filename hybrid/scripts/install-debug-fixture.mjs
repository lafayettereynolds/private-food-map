import { copyFile, mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const destination = resolve(root, 'dist/_hybrid_debug/profile-restaurant-rich.json')
await mkdir(resolve(root, 'dist/_hybrid_debug'), { recursive: true })
await copyFile(resolve(root, 'hybrid/fixtures/profile-restaurant-rich.json'), destination)
console.log('Installed deterministic Debug-only Hybrid fixture.')
