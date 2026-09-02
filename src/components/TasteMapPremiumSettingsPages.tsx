import { useEffect, useState } from 'react'
import { Archive, BellRing, Check, ChevronRight, CircleHelp, Cloud, Database, Download, HardDrive, Info, KeyRound, LockKeyhole, LogOut, MapPin, RefreshCw, ShieldCheck, Sparkles, UserRound } from 'lucide-react'
import type { TasteMapPlatform, TasteMapPremiumStatusDTO, TasteMapProfileDashboardViewModel, TasteMapSyncStatusDTO } from '../platform/TasteMapPlatform'
import { PremiumBurgerBadge } from './PremiumBurgerBadge'
import { HybridEntryRow, HybridPageHeader, HybridState } from './TasteMapHybridShared'

export function TasteMapPremiumPage({ platform, onOpenStore }: { platform: TasteMapPlatform; onOpenStore?: () => void }) {
  const [status, setStatus] = useState<TasteMapPremiumStatusDTO | null>(null)
  useEffect(() => { void platform.premium.status().then(setStatus).catch(() => setStatus({ state: 'unavailable', expiresAt: null })) }, [platform])
  return <main className="tm-hybrid-page tm-hybrid-premium">
    <HybridPageHeader description="会员状态和商品价格始终由 StoreKit / server entitlement 决定。" eyebrow="TASTE MAP PREMIUM" title="Premium" />
    {!status ? <HybridState kind="loading" message="正在读取正式会员权益。" title="确认会员状态" /> : status.state === 'premium' ? <section className="tm-hybrid-premium-active"><PremiumBurgerBadge /><small>Taste Map Premium</small><h2>已开通</h2><p>{status.expiresAt ? `有效期至 ${new Date(status.expiresAt).toLocaleDateString('zh-CN')}` : '当前权益有效'}</p><div><Benefit title="完整口味档案与高级分析" /><Benefit title="最佳饭搭子与谁最会种草" /><Benefit title="本月 / 年度回顾与五类分享海报" /><Benefit title="高级筛选与完整历史洞察" /></div><button onClick={onOpenStore ?? (() => void platform.navigation.openNative({ route: 'premiumStore' }))} type="button">管理会员与恢复购买<ChevronRight size={17} /></button></section> : <>
      <section className="tm-hybrid-premium-hero"><PremiumBurgerBadge /><div><small>让长期记录更有价值</small><h2>把每一次吃饭，变成真正懂你的口味档案。</h2><p>解锁完整分析、回顾与高质量分享海报。真实价格只在 App Store 商品加载成功后展示。</p></div></section>
      <section className="tm-hybrid-premium-benefits"><Benefit title="完整口味档案" detail="高频菜系、消费、城市、饭搭子、时间与代表餐厅。" /><Benefit title="关系与来源洞察" detail="最佳饭搭子、谁最会种草，以及真实结果证据。" /><Benefit title="月度 / 年度回顾" detail="从长期记录中看见口味变化和城市足迹。" /><Benefit title="五类分享海报" detail="统一 Analysis 视觉家族，9:16 高清导出。" /></section>
      <section className="tm-hybrid-premium-comparison"><h3>免费版与 Premium</h3><div><span>能力</span><span>免费版</span><span>Premium</span></div>{[['基础记录', '包含', '包含'], ['完整分析', '摘要', '完整'], ['回顾海报', '—', '包含'], ['高级筛选', '基础', '完整']].map((row) => <div key={row[0]}>{row.map((value) => <span key={value}>{value === '包含' ? <><Check size={13} />包含</> : value}</span>)}</div>)}</section>
      <section className="tm-hybrid-premium-purchase"><h3>App Store 订阅</h3><p>{status.state === 'unavailable' ? '当前 StoreKit 商品尚未加载；Taste Map 不会显示假价格或伪造购买成功。' : '价格将由 App Store 按你的地区和币种提供。'}</p><button onClick={onOpenStore ?? (() => void platform.navigation.openNative({ route: 'premiumStore' }))} type="button"><Sparkles size={17} />查看正式订阅方案</button><button onClick={onOpenStore ?? (() => void platform.navigation.openNative({ route: 'premiumStore' }))} type="button">恢复购买</button></section>
    </>}
  </main>
}

function Benefit({ title, detail }: { title: string; detail?: string }) { return <article><span><Check size={16} /></span><div><strong>{title}</strong>{detail ? <small>{detail}</small> : null}</div></article> }

export function TasteMapSettingsPage({ platform, profile, onOpenPremium, onOpenNativeSettings }: { platform: TasteMapPlatform; profile: TasteMapProfileDashboardViewModel; onOpenPremium?: () => void; onOpenNativeSettings?: () => void }) {
  const [sync, setSync] = useState<TasteMapSyncStatusDTO | null>(null)
  useEffect(() => { void platform.sync.status().then(setSync).catch(() => setSync({ state: 'unavailable', pendingMutationCount: 0, lastSuccessfulSyncAt: null, errorCode: null })) }, [platform])
  const nativeSettings = onOpenNativeSettings ?? (() => void platform.navigation.openNative({ route: 'settingsNative' }))
  return <main className="tm-hybrid-page tm-hybrid-settings">
    <HybridPageHeader description="账户、数据、同步、权限与系统信息。高风险操作继续由正式 Native service 承载。" eyebrow="SETTINGS" title="设置" />
    <SettingsSection title="账户"><HybridEntryRow detail={profile.user.nickname} icon={<UserRound size={18} />} onClick={nativeSettings} title="账户与资料" value={profile.user.membershipTier === 'member' ? 'Premium' : '免费版'} /><HybridEntryRow detail="Taste Map ID、编辑资料与退出登录" icon={<KeyRound size={18} />} onClick={nativeSettings} title="账户安全" /></SettingsSection>
    <SettingsSection title="数据与备份"><HybridEntryRow detail="Backup v1 不包含照片原图" icon={<Download size={18} />} onClick={nativeSettings} title="导出备份" /><HybridEntryRow detail="导入 / 恢复继续使用带预检和确认的原生流程" icon={<Archive size={18} />} onClick={nativeSettings} title="导入与恢复" /><HybridEntryRow detail={`${profile.restaurants.length} 家餐厅 · ${profile.visits.length} 次到访`} icon={<Database size={18} />} title="本地数据概览" /></SettingsSection>
    <SettingsSection title="同步"><HybridEntryRow detail={syncDescription(sync)} icon={<Cloud size={18} />} onClick={nativeSettings} title="同步状态" value={sync?.state === 'idle' ? '正常' : sync?.state === 'syncing' ? '同步中' : sync?.state === 'error' ? '错误' : '查看'} />{sync?.pendingMutationCount ? <HybridEntryRow detail="等待安全上传的本地更改" icon={<RefreshCw size={18} />} title="待同步记录" value={`${sync.pendingMutationCount}`} /> : null}</SettingsSection>
    <SettingsSection title="隐私与权限"><HybridEntryRow detail="资料、到访和食单可见范围" icon={<ShieldCheck size={18} />} onClick={nativeSettings} title="隐私" /><HybridEntryRow detail="定位只在需要附近功能时请求" icon={<MapPin size={18} />} onClick={nativeSettings} title="位置权限" /><HybridEntryRow detail="照片选择与有限图库状态" icon={<BellRing size={18} />} onClick={nativeSettings} title="照片权限" /></SettingsSection>
    <SettingsSection title="存储与 Premium"><HybridEntryRow detail="只清理可再生成缓存，不删除唯一原图或业务数据" icon={<HardDrive size={18} />} onClick={nativeSettings} title="存储" /><HybridEntryRow detail={profile.user.membershipTier === 'member' ? '查看当前权益与订阅管理' : '查看会员能力'} icon={<Sparkles size={18} />} onClick={onOpenPremium ?? (() => void platform.navigation.openHybrid({ surface: 'premium' }))} title="Premium" /></SettingsSection>
    <SettingsSection title="帮助与关于"><HybridEntryRow detail="备份、同步、添加餐厅与定位说明" icon={<CircleHelp size={18} />} onClick={nativeSettings} title="使用帮助" /><HybridEntryRow detail="版本、Build 与已配置法律链接" icon={<Info size={18} />} onClick={nativeSettings} title="关于 Taste Map" /><HybridEntryRow detail="只有正式后端能力存在时才展示删除账户" icon={<LockKeyhole size={18} />} onClick={nativeSettings} title="账户与数据权利" /></SettingsSection>
    <button className="tm-hybrid-settings__logout" onClick={() => void platform.auth.logout()} type="button"><LogOut size={17} />退出登录</button>
  </main>
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) { return <section className="tm-hybrid-settings-section"><h2>{title}</h2><div>{children}</div></section> }

function syncDescription(value: TasteMapSyncStatusDTO | null) {
  if (!value) return '正在读取同步状态'
  if (value.state === 'unavailable') return '在浏览器或未配置环境中不可用'
  if (value.state === 'error') return value.errorCode ? `最近错误：${value.errorCode}` : '最近同步失败'
  if (value.lastSuccessfulSyncAt) return `上次成功：${new Date(value.lastSuccessfulSyncAt).toLocaleString('zh-CN')}`
  return value.state === 'syncing' ? '正在同步' : '尚无成功同步记录'
}
