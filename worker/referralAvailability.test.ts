import { describe, expect, it } from 'vitest'
import { referralAvailable } from '../src/config/referralAvailability'
import { handleAuthV1Request } from './authV1'
import worker from './index'

describe('first TestFlight referral release policy', () => {
  it('defaults closed independently of client input', () => expect(referralAvailable()).toBe(false))
  it('rejects an invitation landing link without reading inventory', async () => {
    const response = await worker.fetch(new Request('https://tastemap.cn/invite/aaaaaaaaaaaaaaaaaaaaaaaa'), {} as never)
    expect(response.status).toBe(404)
  })
  it('blocks a forged registration attribution before touching database or verifier', async () => {
    await expect(handleAuthV1Request(new Request('https://tastemap.cn/api/v1/auth/apple/exchange', {
      method:'POST', body:JSON.stringify({apiVersion:1,referralCode:'aaaaaaaaaaaaaaaaaaaaaaaa'})
    }), {} as never)).rejects.toMatchObject({status:403,code:'referral_unavailable'})
  })
})
