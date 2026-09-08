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
    expect(headings).toEqual(['账户', '会员权益', '邀请奖励', '私人资料', '数据与备份', '同步', '隐私', '权限', '存储', '帮助', '关于'])
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
    expect(html).toContain('决定谁可以查看你的个人主页、味觉足迹和到访照片。食单仍单独设置。')
    expect(html).not.toContain('对应记录中修改')

    // Local canonical source contract only; this does not attest Production deployment.
    const policy = source('../../web-public/public/privacy.html')
    for (const text of [
      '<h1>Taste Map 隐私政策</h1>',
      'Apple MapKit：提供地图、地点搜索和导航等能力',
      'Cloudflare Workers：处理账户认证、数据同步、内容访问控制和会员权益等请求',
      'D1 保存相应结构化记录',
      'R2 保存你选择上传的照片及缩略图',
      'StoreKit 交易标识、原始交易标识、商品 ID、权益状态、有效期、撤销或退款状态以及交易环境',
      'Apple App Store Server API 验证交易',
      'App Store Server Notifications 以更新权益',
      'Taste Map 不收集你的银行卡号或完整支付卡信息',
      '普通删除记录的业务内容保留 30 天后进入清理',
      '账户删除后的到访、餐厅、UGC 内容及私有头像也在 30 天后进入清理',
      '已关闭账户的安全会话在撤销满 90 天后清理',
      '举报记录在最后更新满 90 天后清理',
      '推荐事件在记录或接收满 90 天后清理',
      '账户关闭满 365 天后，相关业务记录、同步历史、删除任务记录和账户记录进入最终物理清理',
      '必要的 Apple 交易及所有权证明保留至账户关闭及相关交易结束／最后更新均已满 365 天',
      '最低限度的权益来源关系会保留到该奖励结束后 365 天',
      '达到保留期限表示进入清理流程，不代表所有系统或备份在同一时刻完成删除',
      '我的 → 设置 → 账户与安全 → 删除账户',
      '按提示重新验证身份和确认',
      '账户停用，已有会话失效，相关公开内容撤下',
      'Apple 身份关联和邮箱会从账户记录中移除',
      '只有待处理清单和重新查询的账户图片范围均为空时，照片清理才视为完成',
      '失败或中断的任务保留可重试状态，不会以成功代替失败',
    ]) expect(policy).toContain(text)
    for (const placeholder of [
      '上线前请在此处列出实际使用的供应商',
      '上线前请确认实际路径并修改此处',
      '如果 Taste Map 提供账号注册功能',
      'Cloudflare Workers / D1 / R2 等实际使用服务',
    ]) expect(policy).not.toContain(placeholder)
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
