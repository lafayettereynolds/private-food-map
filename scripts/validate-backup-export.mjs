import { readFile } from 'node:fs/promises'
import process from 'node:process'
import Ajv2020 from 'ajv/dist/2020.js'

const [, , fixturePath] = process.argv
if (!fixturePath) throw new Error('Usage: node scripts/validate-backup-export.mjs <generated-export.json>')

const [schema, fixture] = await Promise.all([
  readFile(new URL('../contracts/backup/backup.v1.schema.json', import.meta.url), 'utf8').then(JSON.parse),
  readFile(fixturePath, 'utf8').then(JSON.parse),
])
const ajv = new Ajv2020({ allErrors: true, strict: true, multipleOfPrecision: 12 })
const validate = ajv.compile(schema)
if (!validate(fixture)) {
  throw new Error(ajv.errorsText(validate.errors, { separator: '\n' }))
}
process.stdout.write(`Backup v1 JSON Schema valid: ${fixturePath}\n`)
