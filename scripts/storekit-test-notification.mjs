// Operator-only. Reads the existing subscription key into memory; never emits
// keys, JWTs, signed payloads, transaction IDs or notification test tokens.
import { readFileSync } from 'node:fs'
import { AppStoreServerAPIClient, Environment } from '@apple/app-store-server-library'

const [keyPath] = process.argv.slice(2)
const { APP_STORE_KEY_ID, APP_STORE_ISSUER_ID, APP_STORE_BUNDLE_ID } = process.env
if (!keyPath || !APP_STORE_KEY_ID || !APP_STORE_ISSUER_ID || APP_STORE_BUNDLE_ID !== 'com.lafayette.tastemap') {
  console.error('Provide an existing key file path and the configured APP_STORE_KEY_ID / APP_STORE_ISSUER_ID / APP_STORE_BUNDLE_ID. No key generation required.')
  process.exitCode = 1
} else {
  try {
    const client = new AppStoreServerAPIClient(readFileSync(keyPath, 'utf8'), APP_STORE_KEY_ID,
      APP_STORE_ISSUER_ID, APP_STORE_BUNDLE_ID, Environment.SANDBOX)
    const result = await client.requestTestNotification()
    if (!result.testNotificationToken) throw new Error('missing test token')
    let delivered = false
    for (let attempt = 0; attempt < 6; attempt++) {
      await new Promise(resolve => setTimeout(resolve, 5000))
      const status = await client.getTestNotificationStatus(result.testNotificationToken)
      const outcomes = (status.sendAttempts ?? []).map(item => item.sendAttemptResult)
      delivered = outcomes.includes('SUCCESS')
      console.log(JSON.stringify({ environment: 'Sandbox', attempt: attempt + 1, delivered, outcomes }))
      if (delivered) break
    }
    // SUCCESS proves delivery only. Match the verified TEST audit row separately.
    if (!delivered) process.exitCode = 1
  } catch (error) {
    console.error(JSON.stringify({ request: 'Sandbox Request Test Notification',
      httpStatus: Number.isInteger(error.httpStatusCode) ? error.httpStatusCode : null,
      appleError: Number.isInteger(error.apiError) ? error.apiError : null,
      deliveryVerified: false }))
    process.exitCode = 1
  }
}
