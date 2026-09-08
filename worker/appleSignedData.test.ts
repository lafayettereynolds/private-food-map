import { describe, expect, it } from 'vitest'
import { verifyAppleNotification, verifyAppleSignedTransaction } from './appleSignedData'

const env={APP_ENVIRONMENT:'production',APP_STORE_BUNDLE_ID:'com.lafayette.tastemap'}
const fake=(payload:object)=>`${btoa(JSON.stringify({alg:'none'}))}.${btoa(JSON.stringify(payload))}.forged`
describe('Apple signed data trust boundary (real verifier)',()=>{
  it('rejects forged Sandbox notification before any transaction lookup',async()=>{
    await expect(verifyAppleNotification(fake({data:{environment:'Sandbox',bundleId:env.APP_STORE_BUNDLE_ID}}),env))
      .rejects.toMatchObject({status:400,code:'apple_signature_verification_failed'})
  })
  it('rejects a forged Sandbox transaction in a Production deployment',async()=>{
    await expect(verifyAppleSignedTransaction(fake({environment:'Sandbox',bundleId:env.APP_STORE_BUNDLE_ID}),env))
      .rejects.toMatchObject({status:400})
  })
  it('does not accept Xcode or LocalTesting as Apple Sandbox',async()=>{
    await expect(verifyAppleSignedTransaction(fake({environment:'Xcode'}),env)).rejects.toMatchObject({code:'invalid_apple_environment'})
  })
  it('requires Production verifier app identity regardless of the deployment flag',async()=>{
    await expect(verifyAppleSignedTransaction(fake({environment:'Production'}),{...env,APP_ENVIRONMENT:'development'}))
      .rejects.toMatchObject({code:'app_store_apple_id_not_configured'})
  })
  it('requires configured numeric App Apple ID for Production signed data',async()=>{
    await expect(verifyAppleNotification(fake({data:{environment:'Production'}}),env)).rejects.toMatchObject({status:503,code:'app_store_apple_id_not_configured'})
  })
})
