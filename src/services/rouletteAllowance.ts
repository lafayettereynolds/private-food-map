/** Device-local daily allowance, keyed by account and local calendar day. */
export function rouletteAllowanceUsed(storage: Pick<Storage, 'getItem'>, ownerID: string, now = new Date()): boolean {
  try { return storage.getItem(`taste-map:roulette-daily:${ownerID}`) === `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}` } catch { return true }
}
export function consumeRouletteAllowance(storage: Pick<Storage, 'getItem' | 'setItem'>, ownerID: string, premium: boolean, now = new Date()): boolean {
  if (premium) return true
  const day = `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`
  const key = `taste-map:roulette-daily:${ownerID}`
  try {
    if (storage.getItem(key) === day) return false
    storage.setItem(key, day)
    return storage.getItem(key) === day
  } catch { return false }
}
