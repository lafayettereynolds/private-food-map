import { describe, expect, it } from 'vitest'
import { productionReadiness } from './productionReadiness'

describe('production readiness', () => {
  it('does not claim readiness when commerce and administrator are unconfigured', async () => {
    const response = await productionReadiness({
      DB: {prepare:()=>({first:async()=>({count:5})})}, PHOTO_STORAGE:{head:async()=>null},
    } as never)
    expect(response.status).toBe(503)
    expect(await response.json()).toEqual({status:'not_ready',checks:{database:true,photos:true,storeKitConfigured:false,administratorConfigured:false}})
  })
  it('fails closed on unavailable bindings', async () => {
    const response = await productionReadiness({} as never)
    expect(response.status).toBe(503)
    expect((await response.json() as {checks:{database:boolean}}).checks.database).toBe(false)
  })
})
