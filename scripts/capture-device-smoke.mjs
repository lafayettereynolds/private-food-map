import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'

// One explicitly selected installed build, no restart loop or second installation.
const root = path.resolve(import.meta.dirname, '..')
const dir = path.join(root, '.private/device-smoke-2026090802')
const device = '60BBB934-D441-53FB-B8CF-0E3DB5878C4D'
fs.mkdirSync(dir, { recursive: true, mode: 0o700 })
fs.chmodSync(dir, 0o700)
const stamp = new Date().toISOString().replaceAll(':', '-')
const raw = fs.createWriteStream(path.join(dir, `console-${stamp}.log`), { flags: 'wx', mode: 0o600 })
const safe = fs.createWriteStream(path.join(dir, `events-${stamp}.jsonl`), { flags: 'wx', mode: 0o600 })
const run = spawn('xcrun', ['devicectl', 'device', 'process', 'launch', '--device', device,
  '--terminate-existing', '--console', 'com.lafayette.tastemap'], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] })
let pending = ''
run.stdout.on('data', chunk => {
  raw.write(chunk)
  pending += chunk.toString()
  const lines = pending.split('\n'); pending = lines.pop() ?? ''
  for (const line of lines) {
    // Only our deliberately non-content diagnostics enter shareable summaries.
    if (!/^TasteMap(?:BuildIdentity|Diagnostic) /.test(line)) continue
    if (!/^[A-Za-z0-9_ =.\-]+\r?$/.test(line)) continue
    const event = { time: new Date().toISOString(), build: '2026090802', device, event: line.trim() }
    safe.write(JSON.stringify(event) + '\n')
    console.log(JSON.stringify(event))
  }
})
run.stderr.on('data', chunk => raw.write(chunk))
run.on('error', () => { console.error('Device console launch failed; inspect private log.'); process.exitCode = 1 })
run.on('close', code => {
  raw.end(); safe.end()
  console.log(JSON.stringify({ captureEnded: true, code, build: '2026090802' }))
  process.exitCode = code ?? 1
})
console.log(JSON.stringify({ captureStarted: true, build: '2026090802', device, directory: dir }))
