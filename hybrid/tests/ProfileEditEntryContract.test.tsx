import { readFileSync } from 'node:fs'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { AccountPrivacyPage, ProfilePage } from '../../src/components/ProfilePage'
import type { UserProfile } from '../../src/types/domain'
import fixture from '../fixtures/profile-restaurant-rich.json'

vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))
const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')
const user = fixture.profile.user as unknown as UserProfile

describe('Profile explicit editing belongs in Settings', () => {
  for (const membershipTier of ['free', 'member'] as const) {
    it(`${membershipTier} dashboard omits the explicit edit action without losing identity or Premium`, () => {
      const html = renderToStaticMarkup(<ProfilePage user={{ ...user, membershipTier }} onSave={async () => undefined} />)
      expect(html).not.toContain('profile-edit-button')
      expect(html).not.toContain('>编辑资料<')
      expect(html).toContain('aria-label="编辑个人资料"') // Existing avatar behavior is intentionally unchanged.
      expect(html).toContain('aria-label="设置"')
      expect(html).toContain(user.nickname)
      const regions = ['profile-dashboard__avatar', 'profile-dashboard__identity', 'profile-user-id', 'profile-dashboard__social-counts', 'profile-joined-at', 'profile-dashboard__counts--primary', 'profile-quick-actions', '回味', '我的食单', '发现与洞察', '味觉足迹']
      for (const region of regions) expect(html, region).toContain(region)
      for (let index = 1; index < regions.length; index++) expect(html.indexOf(regions[index])).toBeGreaterThan(html.indexOf(regions[index - 1]))
      if (membershipTier === 'member') {
        expect(html).not.toContain('profile-dashboard__identity-actions')
        expect(html).toContain('查看 Premium 会员状态')
        expect(source('../../src/styles/global.css')).toContain('.profile-dashboard--owner .profile-dashboard__identity > .profile-joined-at:last-child { margin-bottom: 0; }')
      } else {
        expect(html.match(/class="profile-premium-entry"/g)).toHaveLength(1)
        expect(html).toContain('开通 Premium')
      }
    })
  }

  it('keeps one real full editor in Account alongside the existing focused shortcuts', () => {
    const html = renderToStaticMarkup(<AccountPrivacyPage user={user} onBack={() => undefined} onSave={async () => undefined} />)
    expect(html.match(/<strong>编辑资料<\/strong>/g)).toHaveLength(1)
    expect(html).toContain('<strong>显示名称</strong>')
    expect(html).toContain('<strong>主页可见范围</strong>')
    const profile = source('../../src/components/ProfilePage.tsx')
    expect(profile).toContain("onClick={onSave ? () => setEditor('all') : undefined}")
    expect(profile).toContain('<ProfileEditorModal')
    const settings = source('../../src/components/TasteMapPremiumSettingsPages.tsx')
    expect(settings).toContain("openNativeSettingsDetail('accountSettings')")
    expect(settings).toContain('platform.navigation.openNative({ route, identifier })')
    expect(settings).not.toContain('title="编辑资料"')
    const app = source('../../src/App.tsx')
    expect(app).toContain("accountSettings: 'account'")
    expect(app).toContain('onSave={updateCurrentUserProfile} section={settingsAccountSection}')
    const host = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRootView.swift')
    expect(host).toContain('case .accountSettings:')
    expect(host).toContain('TasteMapHybridNativeAccountSettingsRoute()')
    expect(host).toContain('AccountSettingsView(')
  })

  it('Native owner and previews share the corrected identity, retaining actual Premium/share and the Settings editor', () => {
    const profile = source('../../ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift')
    const identity = profile.slice(profile.indexOf('private struct ProfileIdentityCard'), profile.indexOf('struct ProfileConnectionMetrics'))
    expect(identity).not.toContain('profile-edit-button')
    expect(identity).not.toContain('Button("编辑资料"')
    expect(identity).toContain('membershipStatus == .free || membershipStatus == .expired || shareEntityID != nil')
    expect(identity).toContain('HStack(spacing: 8) { profileActions }')
    expect(identity).toContain('VStack(alignment: .center, spacing: 8) { profileActions }')
    expect(identity).toContain('Button("Premium", action: onPremium)')
    expect(identity).toContain('PublicShareButton(entityType: .profile, entityID: shareEntityID)')
    const avatar = identity.slice(identity.indexOf('private var avatar:'), identity.indexOf('private var identityContent:'))
    expect(avatar).toContain('ProfileAvatarView(profile: profile, photo: avatarPhoto)')
    expect(avatar).not.toMatch(/Button|onTapGesture/)
    expect(profile.match(/ProfileIdentityCard\(/g)).toHaveLength(2)
    const settings = source('../../ios/TasteMap/TasteMap/Features/Settings/TasteMapSettingsView.swift')
    expect(settings).toContain('profileEditor = .all')
    expect(settings.match(/accessibilityIdentifier\("settings-edit-profile"\)/g)).toHaveLength(1)
    expect(settings).toContain('ProfileEditorSheet(')
  })
})
