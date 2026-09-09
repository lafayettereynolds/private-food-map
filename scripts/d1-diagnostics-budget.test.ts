import { describe, expect, it } from 'vitest'
import { createD1DiagnosticBudget } from './d1-diagnostics-budget.mjs'
describe('remote diagnostic read budget (not business traffic)', () => {
  it('blocks unknown costs, unreviewed plans, broad reads, joins and large single reads before execution', async () => {
    let runs=0
    for (const query of [
      {sql:'SELECT id FROM visits',estimatedRows:1},
      {sql:'SELECT id FROM visits WHERE id=?',localPlanVerified:true},
      {sql:'SELECT * FROM visits LIMIT 1',estimatedRows:1,localPlanVerified:true},
      {sql:'SELECT COUNT(*) FROM visits',estimatedRows:1,localPlanVerified:true},
      {sql:'SELECT id FROM visits WHERE id=?',estimatedRows:1001,localPlanVerified:true},
    ]) await expect(createD1DiagnosticBudget().execute(query,async()=>{runs++;return {}})).rejects.toThrow()
    expect(runs).toBe(0)
  })
  it('reserves concurrent estimates and honors actual reads before the next call', async () => {
    const b=createD1DiagnosticBudget({budget:1000})
    const q={sql:'SELECT id FROM visits WHERE id=?',estimatedRows:500,localPlanVerified:true}
    await b.execute(q,async()=>({meta:{rows_read:800}}))
    expect(b.consumed).toBe(800)
    await expect(b.execute(q,async()=>({}))).rejects.toThrow('budget')
  })
  it('requires a reason and a conservative bound even with override; rejects writes', async () => {
    const b=createD1DiagnosticBudget()
    const overrideReason='Reviewed synthetic fixture diagnostic with bounded cost'
    await b.execute({sql:'SELECT COUNT(*) FROM visits',estimatedRows:1200,overrideReason},async()=>({}))
    await expect(b.execute({sql:'SELECT * FROM visits',overrideReason},async()=>({}))).rejects.toThrow('estimate')
    await expect(b.execute({sql:'DELETE FROM visits',estimatedRows:1,overrideReason},async()=>({}))).rejects.toThrow('read-only')
  })
})
