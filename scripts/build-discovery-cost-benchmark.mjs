import { execFileSync } from 'node:child_process'
import { resolve } from 'node:path'
import { createRequire } from 'node:module'
const require=createRequire(import.meta.url)
const {build}=await import(createRequire(require.resolve('wrangler/package.json')).resolve('esbuild'))
const [output,baseline]=process.argv.slice(2)
if(!output)throw new Error('Usage: node scripts/build-discovery-cost-benchmark.mjs output.mjs [baseline-commit]')
// Freeze only the two optimized readers at a verified revision; use the SAME
// fixture, current full migration harness and other endpoint code on both sides.
const plugins=baseline?[{name:'baseline-readers',setup(builder){
  builder.onLoad({filter:/worker\/discovery(V1|VisitAggregates)\.ts$/},({path})=>({
    contents:execFileSync('git',['show',`${baseline}:worker/${path.split('/').at(-1)}`],{encoding:'utf8'}),
    loader:'ts',resolveDir:resolve('worker'),
  }))
}}]:[]
await build({entryPoints:['scripts/benchmark-discovery-cost.ts'],bundle:true,platform:'node',format:'esm',outfile:output,plugins})
