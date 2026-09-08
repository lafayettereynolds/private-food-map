import { Buffer } from 'node:buffer'
import type { SignedDataVerifier } from '@apple/app-store-server-library'
import { APPLE_ROOT_CA_G3 } from './appleRootCertificate.ts'

export type AppleStoreEnvironment = 'Sandbox' | 'Production'
export interface AppleSignatureConfiguration { APP_STORE_BUNDLE_ID?: string; APP_STORE_APP_APPLE_ID?: string }
export class AppleSignedDataError extends Error {
  constructor(readonly code: string, readonly status = 400) { super(code) }
}
const verifiers = new Map<string, SignedDataVerifier>()

// The unverified field is ONLY a bounded selector for a verifier. It never
// authorizes an API request, ledger write, session scope or entitlement.
export async function verifyAppleSignedData(signed: string, kind: 'transaction' | 'notification', config: AppleSignatureConfiguration) {
  if (signed.length > 512_000 || signed.split('.').length !== 3) throw new AppleSignedDataError('invalid_apple_jws')
  let hint: AppleStoreEnvironment
  try {
    const untrusted = JSON.parse(Buffer.from(signed.split('.')[1], 'base64url').toString('utf8'))
    const value = kind === 'transaction' ? untrusted.environment : (untrusted.data ?? untrusted.summary ?? untrusted.appData)?.environment
    if (value !== 'Sandbox' && value !== 'Production') throw new Error()
    hint = value
  } catch { throw new AppleSignedDataError('invalid_apple_environment') }
  if (config.APP_STORE_BUNDLE_ID !== 'com.lafayette.tastemap') throw new AppleSignedDataError('invalid_store_bundle_configuration', 503)
  const appID = Number(config.APP_STORE_APP_APPLE_ID)
  if (hint === 'Production' && (!Number.isSafeInteger(appID) || appID <= 0)) throw new AppleSignedDataError('app_store_apple_id_not_configured', 503)
  const key = `${hint}:${config.APP_STORE_BUNDLE_ID}:${appID}`
  let verifier = verifiers.get(key)
  if (!verifier) {
    // Apple's dependency initializes randomness. Import within the request,
    // never in Worker global scope; do not weaken Workerd startup restrictions.
    const { Environment, SignedDataVerifier } = await import('@apple/app-store-server-library')
    verifier = new SignedDataVerifier([Buffer.from(APPLE_ROOT_CA_G3)], true,
      hint === 'Sandbox' ? Environment.SANDBOX : Environment.PRODUCTION,
      config.APP_STORE_BUNDLE_ID, hint === 'Production' ? appID : undefined)
    verifiers.set(key, verifier)
  }
  try {
    return kind === 'transaction' ? await verifier.verifyAndDecodeTransaction(signed) : await verifier.verifyAndDecodeNotification(signed)
  } catch { throw new AppleSignedDataError('apple_signature_verification_failed') }
}

// Compatibility names retained for existing operator/test callers; one verifier.
export async function verifyAppleSignedTransaction(signed: string, config: AppleSignatureConfiguration & {APP_ENVIRONMENT?:string}) {
  return verifyAppleSignedData(signed, 'transaction', config)
}
export async function verifyAppleNotification(signed: string, config: AppleSignatureConfiguration & {APP_ENVIRONMENT?:string}) {
  return verifyAppleSignedData(signed, 'notification', config)
}
