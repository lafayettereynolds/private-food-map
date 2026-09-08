// Read-only, credential-free RC handoff diagnostics. No account/transaction data.
import { resolve4, resolve6, resolveCname } from 'node:dns/promises'
import { readFileSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'

const authority = JSON.parse(readFileSync(new URL('../ios/TasteMap/TasteMap/Configuration/ProductionEnvironment.json', import.meta.url), 'utf8'))
const dns = {}
for (const [type, query] of Object.entries({ A: resolve4, AAAA: resolve6, CNAME: resolveCname })) {
  try { dns[type] = await query('api.tastemap.cn') } catch (error) { dns[type] = { error: error.code } }
}
const probes = await Promise.all([
  `${authority.apiBaseURL}/health`,
  `${authority.apiBaseURL}/ready`,
  'https://origin-api.tastemap.cn/health',
  'https://origin-api.tastemap.cn/ready',
  'https://api-dev.tastemap.cn/health',
].map(async url => {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(12000), redirect: 'error' })
    const contentType = response.headers.get('content-type') ?? ''
    // Never echo arbitrary HTTP bodies, cookies, headers, or redirect locations.
    const body = contentType.includes('application/json') ? await response.json() : null
    return { url, status: response.status, json: contentType.includes('application/json'), checks: body?.checks && Object.fromEntries(Object.entries(body.checks).filter(([, v]) => typeof v === 'boolean')) }
  } catch { return { url, reachable: false } }
}))
let inventory = { available: false }
try {
  const db = new DatabaseSync(new URL('../.private/sandbox-offer-codes/inventory.sqlite', import.meta.url).pathname, { readOnly: true })
  inventory = { available: true, states: db.prepare('SELECT state, count(*) AS count FROM codes GROUP BY state').all(), batches: db.prepare('SELECT count(*) AS count, sum(offer_key IS NOT NULL AND offer_identifier IS NOT NULL) AS mapped FROM batches').get() }
  db.close()
} catch { /* Absence of private operator inventory is not a reason to create it. */ }
const officialAPIReady = probes[0].status === 200 && probes[0].json && probes[1].status === 200 && probes[1].json
console.log(JSON.stringify({ checkedAt: new Date().toISOString(), dns, probes, inventory, officialAPIReady, realDeviceEvidence: 'NOT_ASSESSED', cutoverAuthorized: false }, null, 2))
process.exitCode = officialAPIReady ? 0 : 1
