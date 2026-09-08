import { describe, expect, it } from 'vitest'
import { productionReadiness } from './productionReadiness'
import { generateKeyPairSync } from 'node:crypto'

describe('production readiness', () => {
  it('does not claim readiness when commerce and administrator are unconfigured', async () => {
    const response = await productionReadiness({
      DB: {prepare:()=>({first:async()=>({count:7})})}, PHOTO_STORAGE:{head:async()=>null},
    } as never)
    expect(response.status).toBe(503)
    expect(await response.json()).toMatchObject({status:'not_ready',checks:{database:true,photos:true,storeKitConfigured:false},optional:{giftAdmin:{configured:false,blocking:false}}})
  })
  it('fails closed on unavailable bindings', async () => {
    const response = await productionReadiness({} as never)
    expect(response.status).toBe(503)
    expect((await response.json() as {checks:{database:boolean}}).checks.database).toBe(false)
  })
  it('does not require Gift Admin for core readiness and checks actual JWT signing', async () => {
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' })
    const env = {
      DB: {prepare:()=>({first:async()=>({count:7})})}, PHOTO_STORAGE:{head:async()=>null},
      APP_ENVIRONMENT:'production',APPLE_CLIENT_IDS:'com.lafayette.tastemap',
      APP_STORE_BUNDLE_ID:'com.lafayette.tastemap',APP_STORE_APP_APPLE_ID:'123456789',APP_STORE_MONTHLY_PRODUCT_ID:'premium.monthly',
      APP_STORE_YEARLY_PRODUCT_ID:'premium.annual',APP_STORE_API_ENVIRONMENT:'production',
      APP_STORE_ISSUER_ID:'fixture-issuer',APP_STORE_KEY_ID:'fixture-key',
      APP_STORE_PRIVATE_KEY:privateKey.export({type:'pkcs8',format:'pem'}).toString(),
    }
    expect((await productionReadiness(env as never)).status).toBe(200)
    expect((await productionReadiness({...env,APP_STORE_PRIVATE_KEY:'BEGIN PRIVATE KEY invalid'} as never)).status).toBe(503)
  })
})
