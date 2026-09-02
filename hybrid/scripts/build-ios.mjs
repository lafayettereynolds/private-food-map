import { spawnSync } from 'node:child_process'
import { resolve } from 'node:path'

const configurationIndex = process.argv.indexOf('--configuration')
const configuration = configurationIndex >= 0 ? process.argv[configurationIndex + 1] : 'Debug'
if (!['Debug', 'Release'].includes(configuration)) throw new Error(`Unsupported configuration: ${configuration}`)
const genericDevice = process.argv.includes('--generic-device')

const root = resolve(import.meta.dirname, '../..')
const simulatorID = process.env.TASTEMAP_SIMULATOR_UDID || 'E4F3EED9-89D8-405C-B4CB-7CA816CE3405'
const result = spawnSync('xcodebuild', [
  '-project', resolve(root, 'hybrid/capacitor-shell/ios/App/App.xcodeproj'),
  '-scheme', 'App',
  '-configuration', configuration,
  '-destination', genericDevice ? 'generic/platform=iOS' : `platform=iOS Simulator,id=${simulatorID}`,
  '-derivedDataPath', resolve(root, genericDevice ? 'build/hybrid-device-derived-data' : 'build/hybrid-derived-data'),
  ...(genericDevice ? ['CODE_SIGNING_ALLOWED=NO'] : []),
  'build',
], { cwd: root, stdio: 'inherit' })
if (result.status !== 0) process.exit(result.status ?? 1)
