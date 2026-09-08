import { readFileSync } from 'node:fs'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { AccountPrivacyPage, SettingRow } from '../../src/components/ProfilePage'
import { HybridEntryRow } from '../../src/components/TasteMapHybridShared'
import { canAdjustSettingsPermission } from '../../src/components/TasteMapPremiumSettingsPages'
import fixture from '../fixtures/profile-restaurant-rich.json'
import type { UserProfile } from '../../src/types/domain'

vi.mock('@amap/amap-jsapi-loader', () => ({ default: { load: vi.fn() } }))
const user = fixture.profile.user as unknown as UserProfile
const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')

describe('Settings action semantics', () => {
  it('native Settings also puts membership immediately after Account and before data tools', () => {
    const settings = source('../../ios/TasteMap/TasteMap/Features/Settings/TasteMapSettingsView.swift')
    const root = settings.slice(0, settings.indexOf('struct AccountSettingsView'))
    const headings = [...root.matchAll(/Section\("([^\"]+)"\)/g)].map((match) => match[1])
    expect(headings).toEqual(['账户', '会员权益', '数据与备份', '同步', '隐私', '权限', '存储', '帮助', '关于'])
    expect(root.match(/accessibilityIdentifier\("settings-premium-entry"\)/g)).toHaveLength(1)
    expect(root).not.toContain('Section("Premium")')
    expect(root).toContain('PremiumSettingsView(membershipStatusOverride: membershipStatusOverride)')
    const browserModal = source('../../src/components/SettingsModal.tsx')
    expect(browserModal.indexOf('className="settings-membership-entry"')).toBeLessThan(browserModal.indexOf('className="settings-summary"'))
  })
  it('only editable rows expose button and disclosure semantics', () => {
    const factual = renderToStaticMarkup(<SettingRow label="绑定邮箱" value="未绑定" />)
    expect(factual).not.toContain('<button')
    expect(factual).not.toContain('chevron-right')
    const editable = renderToStaticMarkup(<SettingRow label="显示名称" onClick={() => undefined} value="测试用户" />)
    expect(editable).toContain('<button')
    expect(editable).toContain('chevron-right')
  })

  it('busy shared rows cannot start another operation', () => {
    const html = renderToStaticMarkup(<HybridEntryRow detail="正在执行" disabled icon={null} onClick={() => undefined} title="立即同步" />)
    expect(html).toContain('disabled=""')
    expect(renderToStaticMarkup(<HybridEntryRow detail="12 家餐厅" icon={null} title="本地数据概览" />)).not.toContain('<button')
  })

  it('allowed permissions remain adjustable but undecided permissions do not open an unrelated system setting', () => {
    for (const value of ['allowed', 'denied', 'restricted', 'limited'] as const) expect(canAdjustSettingsPermission(value)).toBe(true)
    expect(canAdjustSettingsPermission('notDetermined')).toBe(false)
    expect(canAdjustSettingsPermission(undefined)).toBe(false)
  })

  it('account contains direct edit shortcuts instead of unrelated settings pages', () => {
    const html = renderToStaticMarkup(<AccountPrivacyPage onBack={() => undefined} onSave={async () => undefined} user={user} />)
    expect(html).toContain('账户与安全')
    for (const label of ['显示名称', '主页可见范围', '编辑资料']) expect(html).toMatch(new RegExp(`<button[^>]*>[\\s\\S]*?<strong>${label}</strong>`))
    expect(html).not.toContain('权限管理')
    expect(html).not.toContain('v1.2.0')
    expect(html).not.toContain('谁可以给我发送消息')
  })

  it('privacy links directly to visibility and has no second edit-profile action', () => {
    const html = renderToStaticMarkup(<AccountPrivacyPage onBack={() => undefined} onSave={async () => undefined} section="privacy" user={user} />)
    expect(html).toContain('主页可见范围')
    expect(html).not.toContain('显示名称')
    expect(html).not.toContain('编辑资料')
    expect(html).toContain('对应记录中修改')
  })

  it('every browser detail preserves its requested destination', () => {
    const app = source('../../src/App.tsx')
    expect(app).not.toContain('onOpenNativeSettings={() => setShowSettings(true)}')
    for (const route of ['accountSettings', 'privacySettings', 'permissions', 'helpSettings', 'aboutSettings']) expect(app).toContain(`${route}:`)
    expect(app).toContain("setSettingsDataSection(route === 'storage' ? 'storage'")
    const settings = source('../../src/components/TasteMapPremiumSettingsPages.tsx')
    expect(settings).toContain('onOpenNativeSettings({ route, identifier })')
    expect(settings).toContain('canAdjustSettingsPermission(state)')
    expect(settings).not.toContain('title="同步状态"')
    expect(settings).not.toContain('同步请求已完成。')
  })

  it('native account and privacy reuse one targeted editor and shared editable row', () => {
    const settings = source('../../ios/TasteMap/TasteMap/Features/Settings/TasteMapSettingsView.swift')
    expect(settings).not.toContain('LabeledContent("显示名称"')
    expect(settings).not.toContain('LabeledContent("主页可见范围"')
    expect(settings).not.toContain('LabeledContent("当前可见范围"')
    expect(settings).toContain('profileEditor = .displayName')
    expect(settings).toContain('destination: .visibility')
    const editor = source('../../ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift')
    expect(editor).toContain('displayName: destination.editsIdentity ? displayName : profile.displayName')
    expect(editor).toContain('visibility: destination.editsVisibility ? visibility : profile.visibility')
  })
})
