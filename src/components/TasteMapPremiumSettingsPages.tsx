import { useEffect, useState } from 'react'
import { Archive, BellRing, Camera, Check, ChevronRight, CircleHelp, Cloud, Database, Download, HardDrive, Info, KeyRound, LockKeyhole, LogOut, MapPin, RefreshCw, ShieldCheck, Sparkles, UserRound } from 'lucide-react'
import type { TasteMapPermissionsStatusDTO, TasteMapPlatform, TasteMapPremiumProductDTO, TasteMapPremiumStatusDTO, TasteMapProfileDashboardViewModel, TasteMapSyncStatusDTO } from '../platform/TasteMapPlatform'
import { PremiumBurgerBadge } from './PremiumBurgerBadge'
import { HybridEntryRow, HybridPageHeader, HybridState } from './TasteMapHybridShared'

export function TasteMapPremiumPage({ platform, onOpenStore }: { platform: TasteMapPlatform; onOpenStore?: () => void }) {
  const [status, setStatus] = useState<TasteMapPremiumStatusDTO | null>(null)
  const [products, setProducts] = useState<TasteMapPremiumProductDTO[]>([])
  const [message, setMessage] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    void Promise.all([
      platform.premium.status().catch(() => ({ state: 'unavailable' as const, expiresAt: null })),
      platform.premium.products().catch(() => []),
    ]).then(([nextStatus, nextProducts]) => { setStatus(nextStatus); setProducts(nextProducts) })
  }, [platform])
  const premiumAction = async (action: () => Promise<{ outcome: string; status: TasteMapPremiumStatusDTO }>, success: string) => {
    setBusy(true); setMessage(null)
    try {
      const result = await action()
      setStatus(result.status)
      setMessage(result.outcome === 'cancelled' ? '已取消，没有产生购买。' : result.outcome === 'pending' ? '购买正在等待 App Store 确认。' : success)
    } catch { setMessage('App Store 暂时无法完成这个操作，请稍后再试。') }
    finally { setBusy(false) }
  }
  return <main className="tm-hybrid-page tm-hybrid-premium">
    <HybridPageHeader description="会员状态和商品价格始终由 StoreKit / server entitlement 决定。" eyebrow="TASTE MAP PREMIUM" title="Premium" />
    {!status ? <HybridState kind="loading" message="正在读取正式会员权益。" title="确认会员状态" /> : status.state === 'premium' ? <section className="tm-hybrid-premium-active"><PremiumBurgerBadge /><small>Taste Map Premium</small><h2>已开通</h2><p>{status.expiresAt ? `有效期至 ${new Date(status.expiresAt).toLocaleDateString('zh-CN')}` : '当前权益有效'}</p><div><Benefit title="完整口味档案与高级分析" /><Benefit title="最佳饭搭子与谁最会种草" /><Benefit title="本月 / 年度回顾与五类分享海报" /><Benefit title="高级筛选与完整历史洞察" /></div><button disabled={busy} onClick={onOpenStore ?? (() => void premiumAction(() => platform.premium.manage(), '已打开 App Store 订阅管理。'))} type="button">管理会员<ChevronRight size={17} /></button><button disabled={busy} onClick={() => void premiumAction(() => platform.premium.restore(), '购买记录已恢复，会员状态已刷新。')} type="button">恢复购买</button>{message ? <p role="status">{message}</p> : null}</section> : <>
      <section className="tm-hybrid-premium-hero"><PremiumBurgerBadge /><div><small>让长期记录更有价值</small><h2>把每一次吃饭，变成真正懂你的口味档案。</h2><p>解锁完整分析、回顾与高质量分享海报。真实价格只在 App Store 商品加载成功后展示。</p></div></section>
      <section className="tm-hybrid-premium-benefits"><Benefit title="完整口味档案" detail="高频菜系、消费、城市、饭搭子、时间与代表餐厅。" /><Benefit title="关系与来源洞察" detail="最佳饭搭子、谁最会种草，以及真实结果证据。" /><Benefit title="月度 / 年度回顾" detail="从长期记录中看见口味变化和城市足迹。" /><Benefit title="五类分享海报" detail="统一 Analysis 视觉家族，9:16 高清导出。" /></section>
      <section className="tm-hybrid-premium-comparison"><h3>免费版与 Premium</h3><div><span>能力</span><span>免费版</span><span>Premium</span></div>{[['基础记录', '包含', '包含'], ['完整分析', '摘要', '完整'], ['回顾海报', '—', '包含'], ['高级筛选', '基础', '完整']].map((row) => <div key={row[0]}>{row.map((value) => <span key={value}>{value === '包含' ? <><Check size={13} />包含</> : value}</span>)}</div>)}</section>
      <section className="tm-hybrid-premium-purchase"><h3>App Store 订阅</h3><p>{!products.length ? '当前 StoreKit 商品尚未加载；Taste Map 不会显示假价格或伪造购买成功。' : '以下价格由 App Store 按你的地区和币种提供。'}</p>{products.map((product) => <button disabled={busy} key={product.id} onClick={() => void premiumAction(() => platform.premium.purchase(product.id), '购买已完成，会员状态已刷新。')} type="button"><Sparkles size={17} /><span>{product.displayName}<small>{product.billingPeriodDescription}</small></span><strong>{product.displayPrice}</strong></button>)}<button disabled={busy} onClick={() => void premiumAction(() => platform.premium.restore(), '购买记录已恢复，会员状态已刷新。')} type="button">恢复购买</button>{message ? <p role="status">{message}</p> : null}</section>
    </>}
  </main>
}

function Benefit({ title, detail }: { title: string; detail?: string }) { return <article><span><Check size={16} /></span><div><strong>{title}</strong>{detail ? <small>{detail}</small> : null}</div></article> }

export function TasteMapSettingsPage({ platform, profile, onOpenPremium, onOpenNativeSettings }: { platform: TasteMapPlatform; profile: TasteMapProfileDashboardViewModel; onOpenPremium?: () => void; onOpenNativeSettings?: () => void }) {
  const [sync, setSync] = useState<TasteMapSyncStatusDTO | null>(null)
  const [permissions, setPermissions] = useState<TasteMapPermissionsStatusDTO | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    void platform.sync.status().then(setSync).catch(() => setSync({ state: 'unavailable', pendingMutationCount: 0, lastSuccessfulSyncAt: null, errorCode: null }))
    void platform.permissions.status().then(setPermissions).catch(() => setPermissions(null))
  }, [platform])
  const nativeSettings = onOpenNativeSettings ?? (() => void platform.navigation.openNative({ route: 'settingsNative' }))
  const perform = async (action: () => Promise<unknown>, success?: string) => {
    setBusy(true); setMessage(null)
    try { await action(); if (success) setMessage(success) }
    catch { setMessage('当前系统能力暂时不可用，请稍后再试。') }
    finally { setBusy(false) }
  }
  return <main className="tm-hybrid-page tm-hybrid-settings">
    <HybridPageHeader description="账户、数据、同步、权限与系统信息。高风险操作继续由正式 Native service 承载。" eyebrow="SETTINGS" title="设置" />
    <SettingsSection title="账户"><HybridEntryRow detail={profile.user.nickname} icon={<UserRound size={18} />} onClick={nativeSettings} title="账户与资料" value={profile.user.membershipTier === 'member' ? 'Premium' : '免费版'} /><HybridEntryRow detail="Taste Map ID、编辑资料与退出登录" icon={<KeyRound size={18} />} onClick={nativeSettings} title="账户安全" /></SettingsSection>
    <SettingsSection title="数据与备份"><HybridEntryRow detail="Backup v1 不包含照片原图" icon={<Download size={18} />} onClick={() => void perform(() => platform.backup.openExport())} title="导出备份" /><HybridEntryRow detail="导入使用预检、dry run、明确确认和原子写入" icon={<Archive size={18} />} onClick={() => void perform(() => platform.backup.openImport())} title="导入数据" /><HybridEntryRow detail={`${profile.restaurants.length} 家餐厅 · ${profile.visits.length} 次到访`} icon={<Database size={18} />} title="本地数据概览" /></SettingsSection>
    <SettingsSection title="同步"><HybridEntryRow detail={syncDescription(sync)} icon={<Cloud size={18} />} onClick={() => void perform(async () => setSync(await platform.sync.run()), '同步请求已完成。')} title="同步状态" value={sync?.state === 'idle' ? '正常' : sync?.state === 'syncing' ? '同步中' : sync?.state === 'error' ? '错误' : '查看'} />{sync?.pendingMutationCount ? <HybridEntryRow detail="等待安全上传的本地更改" icon={<RefreshCw size={18} />} title="待同步记录" value={`${sync.pendingMutationCount}`} /> : null}{sync?.pendingPhotoCount ? <HybridEntryRow detail="由现有 PhotoTransferCoordinator 处理" icon={<RefreshCw size={18} />} title="待上传照片" value={`${sync.pendingPhotoCount}`} /> : null}</SettingsSection>
    <SettingsSection title="隐私与权限"><HybridEntryRow detail="资料、到访和食单可见范围" icon={<ShieldCheck size={18} />} onClick={nativeSettings} title="隐私" /><HybridEntryRow detail={permissionDescription(permissions?.location)} icon={<MapPin size={18} />} onClick={permissions?.canOpenSystemSettings ? () => void perform(() => platform.permissions.openSystemSettings()) : undefined} title="位置权限" value={permissionLabel(permissions?.location)} /><HybridEntryRow detail={cameraPermissionDescription(permissions?.camera)} icon={<Camera size={18} />} onClick={permissions?.canOpenSystemSettings ? () => void perform(() => platform.permissions.openSystemSettings()) : undefined} title="相机权限" value={permissionLabel(permissions?.camera)} /><HybridEntryRow detail={permissionDescription(permissions?.photoAddOnly, true)} icon={<BellRing size={18} />} onClick={permissions?.canOpenSystemSettings ? () => void perform(() => platform.permissions.openSystemSettings()) : undefined} title="照片权限" value={permissionLabel(permissions?.photoAddOnly)} /></SettingsSection>
    <SettingsSection title="存储与 Premium"><HybridEntryRow detail="只清理可再生成缓存，不删除唯一原图或业务数据" icon={<HardDrive size={18} />} onClick={nativeSettings} title="存储" /><HybridEntryRow detail={profile.user.membershipTier === 'member' ? '查看当前权益与订阅管理' : '查看会员能力'} icon={<Sparkles size={18} />} onClick={onOpenPremium ?? (() => void platform.navigation.openHybrid({ surface: 'premium' }))} title="Premium" /></SettingsSection>
    <SettingsSection title="帮助与关于"><HybridEntryRow detail="备份、同步、添加餐厅与定位说明" icon={<CircleHelp size={18} />} onClick={nativeSettings} title="使用帮助" /><HybridEntryRow detail="版本、Build 与已配置法律链接" icon={<Info size={18} />} onClick={nativeSettings} title="关于 Taste Map" /><HybridEntryRow detail="重新验证身份后由正式后端执行，不做本地假删除" icon={<LockKeyhole size={18} />} onClick={() => void perform(() => platform.account.openDelete())} title="删除账户" /></SettingsSection>
    {message ? <p className="tm-hybrid-settings__message" role="status">{message}</p> : null}
    <button className="tm-hybrid-settings__logout" disabled={busy} onClick={() => void platform.auth.logout()} type="button"><LogOut size={17} />退出登录</button>
  </main>
}

function permissionLabel(value?: TasteMapPermissionsStatusDTO['location']) {
  return value === 'allowed' ? '已允许' : value === 'limited' ? '有限' : value === 'denied' ? '已拒绝' : value === 'restricted' ? '受限制' : value === 'notDetermined' ? '未请求' : '查看'
}

function permissionDescription(value?: TasteMapPermissionsStatusDTO['location'], photo = false) {
  if (!value) return photo ? '选择照片时使用系统 PhotosPicker' : '只在使用附近功能时请求'
  if (value === 'allowed') return photo ? '系统允许保存生成的分析海报' : '附近功能可使用系统实际位置'
  if (value === 'limited') return '系统当前只提供有限访问，可前往设置调整'
  if (value === 'denied' || value === 'restricted') return '功能仍保持诚实降级；可前往系统设置调整'
  return photo ? '主动保存海报时才会请求权限' : '使用附近功能时才会请求权限'
}

function cameraPermissionDescription(value?: TasteMapPermissionsStatusDTO['camera']) {
  if (!value || value === 'notDetermined') return '只在主动选择“拍照”时请求相机权限'
  if (value === 'allowed') return '可以拍摄本次到访与菜品照片'
  return '相机保持不可用；可前往系统设置调整'
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) { return <section className="tm-hybrid-settings-section"><h2>{title}</h2><div>{children}</div></section> }

function syncDescription(value: TasteMapSyncStatusDTO | null) {
  if (!value) return '正在读取同步状态'
  if (value.state === 'unavailable') return '在浏览器或未配置环境中不可用'
  if (value.state === 'error') return value.errorCode ? `最近错误：${value.errorCode}` : '最近同步失败'
  if (value.lastSuccessfulSyncAt) return `上次成功：${new Date(value.lastSuccessfulSyncAt).toLocaleString('zh-CN')}`
  return value.state === 'syncing' ? '正在同步' : '尚无成功同步记录'
}
