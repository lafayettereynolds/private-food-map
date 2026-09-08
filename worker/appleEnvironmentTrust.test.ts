import { describe, expect, it } from 'vitest'
import { Buffer } from 'node:buffer'
import { verifyAppleSignedData } from './appleSignedData'
const config = {APP_STORE_BUNDLE_ID:'com.lafayette.tastemap',APP_STORE_APP_APPLE_ID:'123456789'}
const fake = (payload: object) => `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.forged`
describe('real Apple signature trust boundary (no cryptographic mock)',()=>{
  it('rejects unsigned Sandbox and Production transaction payloads',async()=>{
    for(const environment of ['Sandbox','Production']) {
      await expect(verifyAppleSignedData(fake({environment,bundleId:config.APP_STORE_BUNDLE_ID}),'transaction',config))
        .rejects.toMatchObject({code:'apple_signature_verification_failed'})
    }
  })
  it('rejects unsigned notification even with the correct app/bundle/environment',async()=>{
    await expect(verifyAppleSignedData(fake({notificationType:'TEST',notificationUUID:'fake',data:{environment:'Sandbox',bundleId:config.APP_STORE_BUNDLE_ID}}),'notification',config))
      .rejects.toMatchObject({code:'apple_signature_verification_failed'})
  })
  it('rejects Xcode/local testing environments and oversized malformed JWS',async()=>{
    for(const environment of ['Xcode','LocalTesting','sandbox','invalid']) {
      await expect(verifyAppleSignedData(fake({environment}),'transaction',config)).rejects.toMatchObject({code:'invalid_apple_environment'})
    }
    await expect(verifyAppleSignedData('x'.repeat(512001),'transaction',config)).rejects.toMatchObject({code:'invalid_apple_jws'})
  })
  it('requires independently configured production App Apple ID',async()=>{
    await expect(verifyAppleSignedData(fake({environment:'Production'}),'transaction',{APP_STORE_BUNDLE_ID:config.APP_STORE_BUNDLE_ID}))
      .rejects.toMatchObject({code:'app_store_apple_id_not_configured',status:503})
  })
})
