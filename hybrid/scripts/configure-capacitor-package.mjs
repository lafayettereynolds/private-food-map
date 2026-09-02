import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '../..')
const packagePath = resolve(root, 'hybrid/capacitor-shell/ios/App/CapApp-SPM/Package.swift')
let source = await readFile(packagePath, 'utf8')

const capacitorDependency = '.package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.5.1")'
const repositoryDependency = '.package(name: "TasteMapRepository", path: "../../../../..")'
const cordovaProduct = '.product(name: "Cordova", package: "capacitor-swift-pm")'
const bridgeProduct = '.product(name: "TasteMapHybridBridge", package: "TasteMapRepository")'

if (!source.includes(repositoryDependency)) {
  source = source.replace(capacitorDependency, `${capacitorDependency},\n        ${repositoryDependency}`)
}
if (!source.includes(bridgeProduct)) {
  source = source.replace(cordovaProduct, `${cordovaProduct},\n                ${bridgeProduct}`)
}

await writeFile(packagePath, source)
console.log('Configured the local TasteMapNative.v1 Swift package dependency.')
