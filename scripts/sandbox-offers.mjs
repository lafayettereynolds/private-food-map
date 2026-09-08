// Local operator tool only. Never import this module into Worker or app bundles.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { randomUUID, createHash } from 'node:crypto'
import { DatabaseSync } from 'node:sqlite'
import { execFileSync } from 'node:child_process'

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const PRIVATE = path.join(ROOT, '.private/sandbox-offer-codes')
export const OFFERS = Object.freeze({
  invitee: { name: '被邀请用户 14 天会员', role: 'invitee', days: 14 },
  ...Object.fromEntries([1, 2, 3, 4, 5].map(slot => [`referrer_${slot}`, { name: `邀请奖励 ${slot}`, role: 'referrer', slot, days: 30 }])),
})
const fail = () => { throw new Error('sandbox_offer_operation_rejected') }
const hash = value => createHash('sha256').update(value).digest('hex')
const iso = () => new Date().toISOString()

// Apple downloads supplied for this task are headerless, single-column CSVs.
// Reject other layouts rather than guessing which field is a secret or an offer.
export function parseCodes(text) {
  const rows = text.replace(/^\uFEFF/, '').split(/\r?\n/).filter(line => line.trim())
  const codes = rows.map(line => line.trim().replace(/^"([A-Z0-9]+)"$/, '$1'))
  if (!codes.length || codes.some(code => !/^[A-Z0-9]{8,32}$/.test(code)) || new Set(codes).size !== codes.length) fail()
  return codes
}

export function openInventory(directory = PRIVATE, environment = 'sandbox') {
  if (environment !== 'sandbox') fail()
  process.umask(0o077)
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 })
  if (fs.lstatSync(directory).isSymbolicLink()) fail()
  fs.chmodSync(directory, 0o700)
  const filename = path.join(directory, 'inventory.sqlite')
  if (fs.existsSync(filename) && fs.lstatSync(filename).isSymbolicLink()) fail()
  const db = new DatabaseSync(filename)
  fs.chmodSync(filename, 0o600)
  db.exec(`PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS inventory_environment(value TEXT PRIMARY KEY CHECK(value='sandbox'));
    INSERT OR IGNORE INTO inventory_environment VALUES('sandbox');
    CREATE TABLE IF NOT EXISTS batches(id TEXT PRIMARY KEY, digest TEXT UNIQUE NOT NULL,
      offer_key TEXT UNIQUE, offer_identifier TEXT UNIQUE, imported_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS codes(id TEXT PRIMARY KEY, batch_id TEXT NOT NULL REFERENCES batches(id),
      secret TEXT UNIQUE NOT NULL, state TEXT NOT NULL DEFAULT 'unused' CHECK(state IN('unused','assigned','redeemed','failed')),
      reward_id TEXT UNIQUE, user_id TEXT, assigned_at TEXT, changed_at TEXT NOT NULL,
      transaction_id TEXT UNIQUE, CHECK((state='unused')=(reward_id IS NULL)));
    CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, code_id TEXT, action TEXT NOT NULL,
      actor TEXT NOT NULL, at TEXT NOT NULL);
    CREATE TRIGGER IF NOT EXISTS audit_no_update BEFORE UPDATE ON audit BEGIN SELECT RAISE(ABORT,'immutable audit'); END;
    CREATE TRIGGER IF NOT EXISTS audit_no_delete BEFORE DELETE ON audit BEGIN SELECT RAISE(ABORT,'immutable audit'); END;`)
  if (!db.prepare('PRAGMA table_info(batches)').all().some(c => c.name === 'source_name')) {
    db.exec('ALTER TABLE batches ADD COLUMN source_name TEXT')
  }
  return db
}
function atomic(db, callback) {
  db.exec('BEGIN IMMEDIATE')
  try { const result = callback(); db.exec('COMMIT'); return result }
  catch { db.exec('ROLLBACK'); fail() }
}
function audit(db, codeID, action) {
  db.prepare('INSERT INTO audit(code_id,action,actor,at) VALUES(?,?,?,?)').run(codeID, action, 'local-sandbox-operator', iso())
}
export function importCSV(db, filename, directory = PRIVATE) {
  const content = fs.readFileSync(filename, 'utf8'), codes = parseCodes(content), digest = hash(content)
  const existing = db.prepare('SELECT id FROM batches WHERE digest=?').get(digest)
  if (existing) {
    db.prepare('UPDATE batches SET source_name=COALESCE(source_name,?) WHERE id=?').run(path.basename(filename), existing.id)
    return { batchID: existing.id, imported: 0, duplicate: true }
  }
  const batchID = randomUUID()
  // Private archival copy. No source basename or original download is tracked.
  const archive = path.join(directory, `${batchID}.csv`)
  fs.writeFileSync(archive, content, { flag: 'wx', mode: 0o600 })
  return atomic(db, () => {
    db.prepare('INSERT INTO batches(id,digest,imported_at,source_name) VALUES(?,?,?,?)').run(batchID, digest, iso(), path.basename(filename))
    for (const code of codes) {
      const id = randomUUID()
      db.prepare('INSERT INTO codes(id,batch_id,secret,changed_at) VALUES(?,?,?,?)').run(id, batchID, code, iso())
      audit(db, id, 'import_unused')
    }
    return { batchID, imported: codes.length, mapping: 'unconfirmed' }
  })
}
export function mapBatch(db, batchID, key, identifier) {
  if (!OFFERS[key] || !identifier || identifier.length > 150) fail()
  return atomic(db, () => {
    const row = db.prepare('SELECT * FROM batches WHERE id=?').get(batchID)
    if (!row || row.offer_key || db.prepare("SELECT 1 FROM codes WHERE batch_id=? AND state<>'unused'").get(batchID)) fail()
    db.prepare('UPDATE batches SET offer_key=?,offer_identifier=? WHERE id=?').run(key, identifier, batchID)
    audit(db, null, `map:${batchID}:${key}`)
    return { mapped: true, offer: OFFERS[key].name }
  })
}

// Read the existing qualified referral ledger; never mint a reward from CLI input.
// The operator must supply a local Sandbox/development SQLite ledger, not Production.
export function eligibleReward(ledger, rewardID) {
  const r = ledger.prepare(`SELECT p.id,p.user_id,p.role,p.days,p.state,r.slot,r.status,r.invitee_id,r.referrer_id
    FROM premium_rewards p JOIN referrals r ON r.invitee_id=p.invitee_id WHERE p.id=?`).get(rewardID)
  if (!r || r.status !== 'qualified' || r.state !== 'active' ||
      r.invitee_id === r.referrer_id || r.slot < 1 || r.slot > 5 ||
      r.user_id !== (r.role === 'invitee' ? r.invitee_id : r.referrer_id)) fail()
  const key = r.role === 'invitee' ? 'invitee' : `referrer_${r.slot}`
  if (!OFFERS[key] || r.days !== OFFERS[key].days) fail()
  if (ledger.prepare(`SELECT 1 FROM membership_entitlements WHERE user_id=? AND status='active'
      AND source='gift_lifetime' AND starts_at<=?`).get(r.user_id, iso())) fail()
  return { ...r, key }
}
export function assign(db, ledger, rewardID) {
  const reward = eligibleReward(ledger, rewardID)
  return atomic(db, () => {
    const old = db.prepare('SELECT id,user_id,state FROM codes WHERE reward_id=?').get(rewardID)
    if (old) {
      if (old.user_id !== reward.user_id) fail()
      return { assignmentID: old.id, state: old.state, duplicate: true }
    }
    const code = db.prepare(`SELECT c.id FROM codes c JOIN batches b ON b.id=c.batch_id
      WHERE c.state='unused' AND b.offer_key=? AND b.offer_identifier IS NOT NULL ORDER BY c.id LIMIT 1`).get(reward.key)
    if (!code) fail()
    db.prepare("UPDATE codes SET state='assigned',reward_id=?,user_id=?,assigned_at=?,changed_at=? WHERE id=? AND state='unused'")
      .run(rewardID, reward.user_id, iso(), iso(), code.id)
    audit(db, code.id, 'assigned')
    return { assignmentID: code.id, state: 'assigned', offer: OFFERS[reward.key].name, days: reward.days }
  })
}
export function markFailed(db, id, reason) {
  if (!['apple_rejected', 'cancelled', 'expired', 'referral_revoked', 'account_mismatch'].includes(reason)) fail()
  return atomic(db, () => {
    const result = db.prepare("UPDATE codes SET state='failed',changed_at=? WHERE id=? AND state='assigned'").run(iso(), id)
    if (!result.changes) fail()
    audit(db, id, `failed:${reason}`)
    return { state: 'failed' }
  })
}
export function handoff(db, ledger, id, directory = PRIVATE) {
  const row = db.prepare("SELECT * FROM codes WHERE id=? AND state='assigned'").get(id)
  if (!row) fail()
  eligibleReward(ledger, row.reward_id)
  const target = path.join(directory, `${id}.redemption.txt`)
  // Exclusive create prevents symlink overwrites. Secret goes only to this private file.
  fs.writeFileSync(target, row.secret, { flag: 'wx', mode: 0o600 })
  audit(db, id, 'private_handoff')
  return { privateFile: target, state: row.state }
}
export async function verifyRedemption(db, ledger, id, transactionID, environment, fetchVerified) {
  if (environment.APP_ENVIRONMENT !== 'development' || environment.APP_STORE_API_ENVIRONMENT !== 'sandbox') fail()
  const row = db.prepare(`SELECT c.*,b.offer_identifier FROM codes c JOIN batches b ON b.id=c.batch_id WHERE c.id=?`).get(id)
  if (!row || !['assigned', 'failed'].includes(row.state) || !/^\d{1,32}$/.test(transactionID)) fail()
  eligibleReward(ledger, row.reward_id)
  const account = ledger.prepare('SELECT app_account_token FROM app_store_accounts WHERE user_id=?').get(row.user_id)
  if (!account) fail()
  // Uses the same authenticated Apple Server API verifier as authoritative commerce.
  const tx = await fetchVerified(transactionID, environment, fetch)
  if (tx.environment !== 'Sandbox' || tx.offerType !== 3 || tx.offerIdentifier !== row.offer_identifier ||
      tx.appAccountToken?.toLowerCase() !== account.app_account_token.toLowerCase() || tx.revocationDate != null ||
      !Number.isFinite(tx.purchaseDate) || tx.purchaseDate < Date.parse(row.assigned_at)) fail()
  return atomic(db, () => {
    eligibleReward(ledger, row.reward_id)
    const result = db.prepare("UPDATE codes SET state='redeemed',transaction_id=?,changed_at=? WHERE id=? AND state IN('assigned','failed')")
      .run(transactionID, iso(), id)
    if (!result.changes) fail()
    audit(db, id, 'redeemed:apple_sandbox_verified_offer_transaction')
    return { state: 'redeemed', evidence: 'verified_sandbox_offer_transaction' }
  })
}
export function serverAssignmentSQL(db, ledger, id) {
  const row = db.prepare(`SELECT c.id,c.user_id,c.reward_id,c.assigned_at,c.state,b.offer_identifier
    FROM codes c JOIN batches b ON b.id=c.batch_id WHERE c.id=?`).get(id)
  if (!row || row.state !== 'assigned' || !row.offer_identifier) fail()
  const reward = eligibleReward(ledger,row.reward_id)
  if (reward.user_id !== row.user_id) fail()
  const q = x => "'" + String(x).replaceAll("'", "''") + "'"
  // All values are assignment metadata. The actual code is never selected.
  return `INSERT INTO sandbox_offer_assignments(assignment_id,user_id,reward_id,offer_identifier,assigned_at)
    SELECT ${q(row.id)},${q(row.user_id)},${q(row.reward_id)},${q(row.offer_identifier)},${q(row.assigned_at)}
    WHERE EXISTS(SELECT 1 FROM premium_rewards p JOIN referrals r ON r.invitee_id=p.invitee_id
      WHERE p.id=${q(row.reward_id)} AND p.user_id=${q(row.user_id)} AND p.state='active' AND r.status='qualified')
    ON CONFLICT(assignment_id) DO NOTHING;
    SELECT COUNT(*) AS assignment_matches FROM sandbox_offer_assignments WHERE assignment_id=${q(row.id)}
      AND user_id=${q(row.user_id)} AND reward_id=${q(row.reward_id)} AND offer_identifier=${q(row.offer_identifier)};`
}

export function syncServerRedemption(db, ledger, id) {
  const row = db.prepare('SELECT c.id,c.user_id,c.state,c.reward_id,b.offer_identifier FROM codes c JOIN batches b ON b.id=c.batch_id WHERE c.id=?').get(id)
  if (!row || !['assigned','failed','redeemed'].includes(row.state)) fail()
  const verified = ledger.prepare(`SELECT a.transaction_id,a.user_id,a.state,a.reward_id,a.offer_identifier,t.environment,t.verification_source
    FROM sandbox_offer_assignments a JOIN app_store_transactions_v2 t ON t.transaction_id=a.transaction_id AND t.environment='Sandbox'
      AND t.user_id=a.user_id AND t.original_transaction_id=a.original_transaction_id
    WHERE a.assignment_id=?`).get(id)
  if (!verified || verified.user_id!==row.user_id || verified.reward_id!==row.reward_id ||
      verified.offer_identifier!==row.offer_identifier || verified.state!=='redeemed' ||
      verified.environment!=='Sandbox' || verified.verification_source!=='app_store_server_api') fail()
  if (row.state==='redeemed') return {state:'redeemed',duplicate:true}
  return atomic(db,()=>{
    db.prepare("UPDATE codes SET state='redeemed',transaction_id=?,changed_at=? WHERE id=? AND state IN('assigned','failed')")
      .run(verified.transaction_id,iso(),id)
    audit(db,id,'redeemed:authoritative_sandbox_server_ledger')
    return {state:'redeemed',evidence:'authoritative_sandbox_server_ledger'}
  })
}

export function summary(db) {
  return db.prepare(`SELECT b.id AS batchID,b.offer_key AS offerKey,
    CASE WHEN b.source_name GLOB 'OfferCodeOneTimeUseCodes_[0-9]*.csv' THEN b.source_name ELSE 'imported-csv' END AS sourceFile,
    COUNT(*) AS total,
    SUM(c.state='unused') AS unused,SUM(c.state='assigned') AS assigned,
    SUM(c.state='redeemed') AS redeemed,SUM(c.state='failed') AS failed
    FROM batches b JOIN codes c ON c.batch_id=b.id GROUP BY b.id ORDER BY b.imported_at,b.id`).all()
}
export function gitGuard(db) {
  const tracked = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: ROOT }).toString().split('\0').filter(Boolean)
  const staged = execFileSync('git', ['diff', '--cached', '--name-only', '-z'], { cwd: ROOT }).toString().split('\0').filter(Boolean)
  if ([...tracked, ...staged].some(f => f.startsWith('.private/') || /OfferCodeOneTimeUseCodes_.*\.csv$/.test(f))) fail()
  const secrets = db.prepare('SELECT secret FROM codes').all().map(r => Buffer.from(r.secret))
  for (const f of tracked) {
    let content
    try { content = fs.readFileSync(path.join(ROOT, f)) } catch { continue }
    if (secrets.some(s => content.includes(s))) fail()
  }
  // Check index blobs too: a clean working copy does not prove the index is safe.
  for (const f of staged) {
    let content
    try { content = execFileSync('git', ['show', `:${f}`], { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }) } catch { continue }
    if (secrets.some(s => content.includes(s))) fail()
  }
  return { gitSafe: true, trackedFilesChecked: tracked.length, stagedFilesChecked: staged.length }
}

function assertSandboxTarget() {
  const config=JSON.parse(fs.readFileSync(path.join(ROOT,'wrangler.development.jsonc'),'utf8'))
  if(config.name!=='private-food-map-development' || config.vars.APP_ENVIRONMENT!=='development' ||
    config.vars.APP_STORE_API_ENVIRONMENT!=='sandbox' || config.d1_databases[0].database_id!=='b1ddde34-c459-49bb-b9d1-7a41303ccb2d') fail()
}
function refreshLedger() {
  assertSandboxTarget()
  const sql=path.join(PRIVATE,`${randomUUID()}.snapshot.sql`), next=path.join(PRIVATE,`${randomUUID()}.snapshot.sqlite`)
  let target
  try {
    execFileSync('pnpm',['exec','wrangler','d1','export','food-map-db-development','--remote','--config','wrangler.development.jsonc','--output',sql],{cwd:ROOT,stdio:'pipe'})
    target=new DatabaseSync(next);target.exec(fs.readFileSync(sql,'utf8'));target.close();target=null
    fs.chmodSync(next,0o600);fs.renameSync(next,path.join(PRIVATE,'sandbox-ledger.sqlite'))
    return {refreshed:true,environment:'sandbox'}
  } finally {
    target?.close()
    for(const file of [sql,next]) if(fs.existsSync(file)) fs.unlinkSync(file)
  }
}

async function main() {
  const [command, ...args] = process.argv.slice(2)
  const at = args.indexOf('--environment')
  if (at < 0 || args[at + 1] !== 'sandbox') fail()
  args.splice(at, 2)
  const db = openInventory()
  let ledger
  try {
    let result
    if (command === 'refresh-ledger') result = refreshLedger()
    else if (command === 'import') result = args.map(f => importCSV(db, f))
    else if (command === 'status') result = summary(db)
    else if (command === 'map') result = mapBatch(db, ...args)
    else if (command === 'fail') result = markFailed(db, ...args)
    else if (command === 'git-guard') result = gitGuard(db)
    else if (['assign', 'handoff', 'verify', 'publish', 'sync-redemption'].includes(command)) {
      const [ledgerFile, id, transactionID, configFile] = args
      if (!ledgerFile || !path.resolve(ledgerFile).startsWith(PRIVATE + path.sep) || !fs.existsSync(ledgerFile) ||
          !fs.realpathSync(ledgerFile).startsWith(fs.realpathSync(PRIVATE) + path.sep)) fail()
      ledger = new DatabaseSync(ledgerFile, { readOnly: true })
      if (command === 'assign') result = assign(db, ledger, id)
      else if (command === 'handoff') result = handoff(db, ledger, id)
      else if (command === 'sync-redemption') result = syncServerRedemption(db,ledger,id)
      else if (command === 'publish') {
        assertSandboxTarget()
        const target=path.join(PRIVATE,`${id}.assignment.sql`)
        fs.writeFileSync(target,serverAssignmentSQL(db,ledger,id),{flag:'wx',mode:0o600})
        try {
          const response=JSON.parse(execFileSync('pnpm',['exec','wrangler','d1','execute','food-map-db-development','--remote','--config','wrangler.development.jsonc','--file',target,'--json'],{cwd:ROOT,stdio:'pipe'}).toString())
          if (!response.some(r=>r.success && r.results?.some(row=>row.assignment_matches===1))) fail()
          result={published:true,assignmentID:id,environment:'sandbox'}
        } finally { fs.unlinkSync(target) }
      }
      else {
        if (!path.resolve(configFile ?? '').startsWith(PRIVATE + path.sep)) fail()
        const configuration = JSON.parse(fs.readFileSync(configFile, 'utf8'))
        const { fetchVerifiedTransaction } = await import('../worker/appStoreCommerceV1.ts')
        result = await verifyRedemption(db, ledger, id, transactionID, configuration, fetchVerifiedTransaction)
      }
    } else fail()
    console.log(JSON.stringify(result))
  } finally { ledger?.close(); db.close() }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error('Sandbox offer operation rejected. Check mapping, eligibility, state and private configuration. No secret details logged.'); process.exitCode = 1 })
}
