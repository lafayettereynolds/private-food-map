/** Product retention choices, not a claim of statutory minimum retention. */
export const PRIVACY_RETENTION = Object.freeze({
  recordContentDays: 30,
  accountContentDays: 30,
  securityDays: 90,
  commerceDays: 365,
  objectBatch: 50,
  recordBatch: 500,
  leaseSeconds: 300,
  maxObjectPages: 100,
  jobBatch: 5,
})
export const retentionCutoff = (now: Date, days: number) => new Date(now.getTime() - days * 86400000).toISOString()
