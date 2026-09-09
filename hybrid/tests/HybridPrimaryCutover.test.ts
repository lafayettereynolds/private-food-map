import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')
describe('authorized Hybrid Primary cutover', () => {
  it('keeps the recovered local namespace independent of the Internal API endpoint', () => {
    const api = source('../../ios/TasteMap/TasteMap/Configuration/AppEnvironment.swift')
    const storage = api.split('static var current: Self')[1].split('nonisolated enum APIConfigurationError')[0]
    expect(storage).toMatch(/#if DEBUG \|\| TASTEMAP_SANDBOX_BUILD\s+\.development\s+#else\s+\.production/)
    expect(storage).not.toContain('|| TASTEMAP_INTERNAL_BUILD')
    const app = source('../../ios/TasteMap/TasteMap/TasteMapApp.swift')
    expect(app.match(/TasteMapAppEnvironment.current == \.development \? "TasteMapDevelopment" : "TasteMap"/g)).toHaveLength(2)
    expect(app).toContain('category=storage event=container_open name=\\(persistenceConfigurationName) apiEnvironment=\\(authConfiguration.environment.rawValue)')
    expect(source('../../ios/TasteMap/TasteMap/Services/KeychainCredentialStore.swift')).toContain('APIConfiguration.current().environment == .development')
    expect(source('../../ios/TasteMap/TasteMap/Services/PremiumEntitlementCache.swift')).toContain('TasteMapAppEnvironment.current == .development')
    expect(source('../../ios/TasteMap/TasteMap/Services/SocialCollaborationOutbox.swift')).toContain('TasteMapAppEnvironment.current == .development ? "TasteMapDevelopment/SocialOutbox" : "TasteMap/SocialOutbox"')
  })
  it('forwards ordinary Universal Links while keeping referral attribution disabled', () => {
    const root = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRootView.swift')
    const handler = root.split('.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)')[1].split('.alert(')[0]
    expect(handler).toContain('guard let url = activity.webpageURL else { return }')
    expect(handler).toContain('url.path.hasPrefix("/invite/") && !ReferralInvitationStore.isAvailable { return }')
    expect(handler).toContain('runtime.receive(url: url)')
    expect(handler.indexOf('!ReferralInvitationStore.isAvailable')).toBeLessThan(handler.indexOf('runtime.receive(url: url)'))
  })
  it('selects the persistent shared root in Release and retains Native rollback', () => {
    const config = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntimeConfiguration.swift')
    expect(config).toMatch(/#else\s+return \.hybridPrimary\s+#endif/)
    const root = source('../../ios/TasteMap/TasteMap/ContentView.swift').split('private var rootView: some View')[1].split('@MainActor')[0]
    expect(root).toContain('hybridRuntime.mode == .nativePrimary')
    expect(root).toContain('RootTabView()')
    expect(root).toContain('TasteMapHybridRootView()')
    expect(root).not.toContain('#if DEBUG')
  })
  it('isolates the Internal endpoint without Sandbox purchasing UI or debug permissions', () => {
    const config = source('../../ios/TasteMap/Configuration/ReleaseInternal.xcconfig')
    expect(config).toContain('$(inherited) TASTEMAP_INTERNAL_BUILD')
    expect(config).not.toMatch(/= .*\b(DEBUG|TASTEMAP_SANDBOX_BUILD|TASTEMAP_PRIVATE_PREVIEW|TASTEMAP_QA)\b/)
    expect(config).not.toContain('INFOPLIST_FILE =')
    const api = source('../../ios/TasteMap/TasteMap/Configuration/AppEnvironment.swift')
    const branch = api.split('#elseif TASTEMAP_INTERNAL_BUILD')[1].split('#elseif')[0]
    expect(branch).toContain('https://api-dev.tastemap.cn')
    expect(branch).not.toContain('processInfo.environment')
    expect(source('../../ios/TasteMap/TasteMap/Features/Premium/PremiumViews.swift')).not.toContain('TASTEMAP_INTERNAL_BUILD')
  })
})
