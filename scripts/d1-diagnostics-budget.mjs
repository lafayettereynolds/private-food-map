/** Remote diagnostics only; never imported by a production request handler.
 * Estimates require local-plan evidence. LIMIT is NOT a scanned-row estimate.
 */
export function createD1DiagnosticBudget({ budget = 10_000, perQuery = 1_000 } = {}) {
  let charged = 0
  return {
    get consumed() { return charged },
    async execute({ sql, estimatedRows, localPlanVerified = false, overrideReason = '' }, run) {
      const override = overrideReason.trim().length >= 20
      const known = Number.isSafeInteger(estimatedRows) && estimatedRows >= 0
      const simpleRead = /^\s*(SELECT|EXPLAIN)\b/i.test(sql) && !/;\s*\S/.test(sql.replace(/;\s*$/, ''))
      const broad = /SELECT\s+\*|COUNT\s*\(\s*\*\s*\)|\bJOIN\b/i.test(sql)
      if (!simpleRead) throw new Error('Diagnostics accepts a single read-only statement only.')
      if ((!known || estimatedRows > perQuery || broad || !localPlanVerified) && !override) {
        throw new Error('Run local EXPLAIN/fixture first; unknown, broad or >1000-row queries require an explicit reviewed override reason.')
      }
      if (!known) throw new Error('Even an override requires a conservative row estimate.')
      if (charged + estimatedRows > budget && !override) throw new Error('Diagnostic round read budget exceeded.')
      // Reserve before execution so parallel calls cannot overspend the estimate.
      charged += estimatedRows
      const result = await run()
      const actual = result?.meta?.rows_read ?? result?.meta?.rowsRead
      if (Number.isFinite(actual)) charged += Math.max(0, actual - estimatedRows)
      // On failure or missing metadata retain the conservative reservation.
      return result
    },
  }
}
